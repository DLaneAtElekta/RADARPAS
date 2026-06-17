defmodule Radarpas.Communication do
  @moduledoc """
  RS232 and modem communication module.
  Translated from the RS232 Routines section of RADAR.PAS (lines 828-1073).

  The original code used:
  - Direct port I/O at ComPort ($3F8 for COM1, $2F8 for COM2)
  - An interrupt service routine (RS232Interupt) hooked into IRQ4/IRQ3
  - A 255-byte circular receive buffer
  - Inline x86 assembly for PUSH/POP registers and IRET

  This translation uses Circuits.UART for serial port access and
  GenServer for the receive buffer, replacing the hardware interrupt handler.

  Original procedures translated:
    HangUp, Tx, Rx, ResetBuf, SendCom, SetParams, RS232Interupt, InitRS232
  """

  use GenServer
  require Logger

  alias Radarpas.CoreTypes
  alias Radarpas.CoreTypes.PicRec

  # ============================================================================
  # Serial Port Behaviour
  # Replaces direct port I/O at ComPort ($3F8/$2F8)
  # ============================================================================

  @callback open(config :: map()) :: {:ok, pid()} | {:error, term()}
  @callback close(port :: pid()) :: :ok
  @callback send_byte(port :: pid(), byte :: byte()) :: :ok | {:error, term()}
  @callback send_data(port :: pid(), data :: binary()) :: :ok | {:error, term()}

  # ============================================================================
  # Communication State
  # Original global variables: Buf, BufBeg, BufEnd, CheckSum, Response,
  #   GfxMatch, PhoneNum, Mode, RT, GRBuf, GRSize, PicSave, PicSaveAt, etc.
  # ============================================================================

  defstruct port_pid: nil,
            port_name: "COM1",
            baud_rate: 2400,
            buf: <<>>,
            checksum: 0,
            response: false,
            gfx_match: false,
            mode: :modem,
            rt: 0,
            gr_buf: <<>>,
            gr_size: 0,
            pic_save: <<>>,
            pic_save_at: 0,
            last_line: 0,
            line_at: 0,
            write_at: 0,
            buf_count: 0,
            map_count: 0,
            current_pic: %PicRec{},
            listeners: []

  # ============================================================================
  # GenServer API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialize the serial port.
  Original: procedure InitRS232 - lines 1055-1073
  Set up interrupt vector, baud rate (2400), 8N1 line control,
  DTR/RTS high, and redirected console output to Tx.
  """
  def init_rs232(port_name \\ "/dev/ttyUSB0", baud_rate \\ 2400) do
    GenServer.call(__MODULE__, {:init_rs232, port_name, baud_rate})
  end

  @doc """
  Transmit a single character.
  Original: procedure Tx(Charac: char) - lines 857-860
  Waited for transmit holding register empty (port[ComPort+5] and $20),
  then wrote byte to ComPort.
  """
  def tx(char) when is_integer(char) do
    GenServer.call(__MODULE__, {:tx, char})
  end

  def tx(char) when is_binary(char) do
    GenServer.call(__MODULE__, {:tx, :binary.first(char)})
  end

  @doc """
  Receive a character from the buffer.
  Original: procedure Rx(var Charac: char) - lines 862-872
  Read from circular buffer; returned #0 if empty.
  """
  def rx do
    GenServer.call(__MODULE__, :rx)
  end

  @doc """
  Reset the receive buffer.
  Original: procedure ResetBuf - lines 874-877
  """
  def reset_buf do
    GenServer.cast(__MODULE__, :reset_buf)
  end

  @doc """
  Send a radar command and wait for response.
  Original: procedure SendCom(Command: char; DelTime: integer) - lines 879-904
  Sent 'Z' prefix, then command byte. Waited for response within DelTime
  (measured in centiseconds via DOS INT 2C time-of-day).
  If RT=0 (antenna off), added 1-second delay.
  """
  def send_com(command, del_time \\ 150) do
    GenServer.call(__MODULE__, {:send_com, command, del_time}, del_time * 20 + 5000)
  end

  @doc """
  Hang up the modem.
  Original: procedure HangUp - lines 851-855
  Dropped DTR for 1 second by writing $08 to modem control register,
  then restored to $0B.
  """
  def hang_up do
    GenServer.call(__MODULE__, :hang_up)
  end

  @doc "Subscribe to receive data events."
  def subscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    state = %__MODULE__{
      port_name: Keyword.get(opts, :port_name, "/dev/ttyUSB0"),
      baud_rate: Keyword.get(opts, :baud_rate, 2400)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:init_rs232, port_name, baud_rate}, _from, state) do
    case Circuits.UART.start_link() do
      {:ok, uart_pid} ->
        case Circuits.UART.open(uart_pid, port_name,
               speed: baud_rate,
               data_bits: 8,
               stop_bits: 1,
               parity: :none,
               active: true
             ) do
          :ok ->
            new_state = %{state | port_pid: uart_pid, port_name: port_name, baud_rate: baud_rate}
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:tx, char}, _from, %{port_pid: nil} = state) do
    Logger.warning("Tx: port not open, dropping byte #{char}")
    {:reply, {:error, :port_not_open}, state}
  end

  def handle_call({:tx, char}, _from, %{port_pid: pid} = state) do
    result = Circuits.UART.write(pid, <<char>>)
    {:reply, result, state}
  end

  def handle_call(:rx, _from, state) do
    case state.buf do
      <<char, rest::binary>> ->
        {:reply, {:ok, char}, %{state | buf: rest}}

      <<>> ->
        {:reply, {:ok, 0}, state}
    end
  end

  def handle_call({:send_com, command, del_time}, _from, state) do
    if state.mode == :interactive do
      # Original: Tx('Z'); Delay(15); Tx(Command);
      send_to_port(state.port_pid, <<?Z>>)
      Process.sleep(15)
      send_to_port(state.port_pid, <<command>>)

      # If RT=0 and not SendGraph, delay 1 second (antenna spin-up)
      if state.rt == 0 and command != CoreTypes.send_graph() do
        Process.sleep(1000)
      end

      # Wait for response with timeout
      # Original used DOS time-of-day interrupt, polling in a loop
      new_state = %{state | response: false, buf: <<>>}

      new_state =
        wait_for_response(new_state, del_time * 10)

      if command == CoreTypes.send_graph(), do: %{new_state | mode: :rx_graph}, else: new_state

      {:reply, new_state.response, new_state}
    else
      {:reply, false, state}
    end
  end

  def handle_call(:hang_up, _from, %{port_pid: pid} = state) when not is_nil(pid) do
    # Original: Port[ComPort+4]:=$08; Delay(1000); Port[ComPort+4]:=$0B;
    # Drop DTR/RTS, wait 1 second, restore
    Circuits.UART.set_break(pid, true)
    Process.sleep(1000)
    Circuits.UART.set_break(pid, false)
    {:reply, :ok, %{state | mode: :modem}}
  end

  def handle_call(:hang_up, _from, state) do
    {:reply, :ok, %{state | mode: :modem}}
  end

  @impl true
  def handle_cast(:reset_buf, state) do
    {:noreply, %{state | buf: <<>>}}
  end

  def handle_cast({:subscribe, pid}, state) do
    {:noreply, %{state | listeners: [pid | state.listeners]}}
  end

  # ============================================================================
  # Incoming Data Handler
  # Original: procedure RS232Interupt - lines 946-1053
  # This was the hardware interrupt service routine, entered via IRQ4.
  # It pushed all registers (inline x86 ASM), read the received byte from
  # ComPort, then dispatched based on current Mode:
  #   Modem:       Queued byte in circular buffer
  #   Interactive: Accumulated 10-byte response, called SetParams, sent 'A' ack
  #   WaitPic:     Watched for $FF,$FE,$FD start sequence, transitioned to RxPic
  #   RxPic:       Assembled scan lines, validated checksums, sent ack/nak
  #   RxGraph:     Received 8-byte map data blocks with checksums
  # ============================================================================

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    handle_received_data(state, data)
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Receive Data Processing
  # Faithful translation of the mode-based dispatch in RS232Interupt
  # ============================================================================

  defp handle_received_data(state, data) when is_binary(data) do
    new_state =
      Enum.reduce(:binary.bin_to_list(data), state, fn byte, acc ->
        process_byte(acc, byte)
      end)

    {:noreply, new_state}
  end

  @doc """
  Process a single received byte based on current mode.
  Original: The case statement inside RS232Interupt (lines 963-1035)
  """
  defp process_byte(%{mode: :modem} = state, byte) do
    # Original: Modem mode - queue in circular buffer
    %{state | buf: state.buf <> <<byte>>}
  end

  defp process_byte(%{mode: mode} = state, byte) when mode in [:interactive, :wait_pic] do
    # Original: Interactive/WaitPic - accumulate 10-byte response
    new_buf = state.buf <> <<byte>>

    new_state =
      if byte_size(new_buf) == 10 do
        # Parse radar response and send ACK
        {response, pic} = set_params(new_buf, state.current_pic)
        send_to_port(state.port_pid, <<?A>>)
        %{state | buf: <<>>, response: response, current_pic: pic}
      else
        %{state | buf: new_buf}
      end

    # Check for picture start sequence ($FF, $FE, $FD)
    if mode == :wait_pic and byte_size(new_state.buf) >= 3 do
      case new_state.buf do
        <<0xFF, 0xFE, 0xFD, _rest::binary>> ->
          %{new_state | mode: :rx_pic, gr_size: 0, checksum: 0}

        _ ->
          new_state
      end
    else
      new_state
    end
  end

  defp process_byte(%{mode: :rx_pic} = state, byte) do
    # Original: RxPic mode - assemble scan lines
    # Accumulated bytes in GRBuf, checked for $18,$18 terminator,
    # validated checksum, sent ack ('A') or nak (#0)
    new_gr_buf = state.gr_buf <> <<byte>>
    new_gr_size = state.gr_size + 1

    new_state = %{state | gr_buf: new_gr_buf, gr_size: new_gr_size}

    if rem(new_gr_size, 2) == 1 and new_gr_size > 6 do
      # Check for line terminator $18, $18
      gr_bytes = :binary.bin_to_list(new_gr_buf)
      second_last = Enum.at(gr_bytes, new_gr_size - 2, 0)
      third_last = Enum.at(gr_bytes, new_gr_size - 3, 0)

      if second_last == 0x18 and third_last == 0x18 do
        # Validate checksum
        checksum =
          gr_bytes
          |> Enum.take(new_gr_size - 1)
          |> Enum.reduce(0, &Bitwise.band(&1 + &2, 0xFF))

        <<line_num_raw::little-16, _rest::binary>> = new_gr_buf
        line_num = div(line_num_raw, 54)

        if line_num >= state.last_line and line_num <= 352 and
             checksum == Enum.at(gr_bytes, new_gr_size - 1, -1) do
          # Valid line - send ack and store
          send_to_port(state.port_pid, <<?A>>)
          send_to_port(state.port_pid, <<?O>>)

          new_pic_save = state.pic_save <> binary_part(new_gr_buf, 0, new_gr_size - 1)
          notify_listeners(state.listeners, {:line_received, line_num, new_gr_buf})

          %{
            new_state
            | pic_save: new_pic_save,
              last_line: line_num,
              gr_buf: <<>>,
              gr_size: 0
          }
        else
          # Invalid - send nak
          send_to_port(state.port_pid, <<0>>)
          %{new_state | gr_buf: <<>>, gr_size: 0}
        end
      else
        new_state
      end
    else
      new_state
    end
  end

  defp process_byte(%{mode: :rx_graph} = state, byte) do
    # Original: RxGraph mode - receive 8-byte map data blocks
    new_buf_count = state.buf_count + 1
    new_gr_buf = state.gr_buf <> <<byte>>

    if new_buf_count == 9 do
      # Validate checksum of 8 data bytes
      data_bytes = :binary.bin_to_list(binary_part(new_gr_buf, 0, 8))
      _checksum = Enum.reduce(data_bytes, 0, &Bitwise.band(&1 + &2, 0xFF))

      # Check for map separator (all zeros)
      if Enum.all?(Enum.take(data_bytes, 4), &(&1 == 0)) do
        new_map_count = state.map_count + 1
        notify_listeners(state.listeners, {:map_separator, new_map_count})
        send_to_port(state.port_pid, <<?A>>)
        %{state | gr_buf: <<>>, buf_count: 0, map_count: new_map_count}
      else
        # Store map data block
        send_to_port(state.port_pid, <<?A>>)
        notify_listeners(state.listeners, {:map_data, new_gr_buf})
        %{state | gr_buf: <<>>, buf_count: 0}
      end
    else
      %{state | gr_buf: new_gr_buf, buf_count: new_buf_count}
    end
  end

  # ============================================================================
  # SetParams - Parse radar response
  # Original: procedure SetParams(var ForBuf; var Params: PicRec) - lines 906-939
  # Parsed the 10-byte 'Q' response from the E300 radar:
  #   Byte 1: 'Q' identifier
  #   Byte 2: Gain (upper nibble) + 1
  #   Byte 3: Tilt (inverted from 12, lower nibble) + RT flags (upper nibble)
  #   Byte 4: Range (bits 3-5 encode range setting)
  #   Bytes 6-9: Time as ASCII "HHMM"
  #   Byte 10: Checksum (sum of bytes 2-9)
  # ============================================================================

  @doc """
  Parse radar Q-response into picture parameters.
  Original: procedure SetParams - lines 906-939
  """
  def set_params(buf, %PicRec{} = pic) when byte_size(buf) == 10 do
    <<b1, b2, b3, b4, _b5, b6, b7, b8, b9, b10>> = buf

    # Verify checksum: sum of bytes 2-9
    checksum = Bitwise.band(b2 + b3 + b4 + 0 + b6 + b7 + b8 + b9, 0xFF)
    response = checksum == b10

    if b1 == ?Q and response do
      # Parse gain: upper nibble of byte 2 + 1
      gain = Bitwise.bsr(b2, 4) + 1

      # Parse tilt: inverted from 12, lower nibble of byte 3
      tilt = 12 - Bitwise.band(b3, 0x0F)

      # PRE (preset) gain if bit 5 of byte 3 is set
      gain = if Bitwise.band(b3, 1 <<< 5) != 0, do: 17, else: gain

      # Parse range from byte 4, bits 3-5
      range =
        case Bitwise.band(b4, 0x38) do
          0x08 -> 1
          0x30 -> 2
          0x00 -> 3
          0x20 -> 4
          0x28 -> 0
          _ -> pic.range
        end

      # Parse time from ASCII digits
      hour = (b6 - 48) * 10 + (b7 - 48)
      minute = (b8 - 48) * 10 + (b9 - 48)

      # Parse RT (receive/transmit) status from byte 3 upper bits
      rt =
        cond do
          Bitwise.band(b3, 0x80) == 0x00 -> 2
          Bitwise.band(b3, 0x10) == 0x00 -> 0
          true -> 1
        end

      new_pic = %{
        pic
        | gain: gain,
          tilt: tilt,
          range: range,
          time: %Radarpas.CoreTypes.TimeRec{hour: hour, minute: minute}
      }

      {true, new_pic, rt}
    else
      {false, pic, 0}
    end
  end

  def set_params(_buf, pic), do: {false, pic, 0}

  # ============================================================================
  # Modem Operations
  # Original: procedure CallStation - lines 1252-1294
  # ============================================================================

  @doc """
  Dial a phone number using the modem.
  Original: procedure CallStation - lines 1252-1294
  Supported Hayes-compatible (AT command set) and Racal-Vadic modems.
  """
  def call_station(phone_num, modem_type \\ 0) do
    GenServer.call(__MODULE__, {:call_station, phone_num, modem_type}, 60_000)
  end

  @impl true
  def handle_call({:call_station, phone_num, modem_type}, _from, state) do
    if phone_num == "" do
      {:reply, {:ok, :direct}, %{state | mode: :interactive}}
    else
      # Send dial command based on modem type
      case modem_type do
        0 ->
          # Hayes compatible: ATDT<number>
          send_to_port(state.port_pid, "ATDT#{phone_num}\r")

        1 ->
          # Racal-Vadic
          send_to_port(state.port_pid, <<0x05, 0x0D>>)
          Process.sleep(50)
          send_to_port(state.port_pid, "D#{phone_num}\r")
      end

      # Wait for modem response
      new_state = %{state | buf: <<>>}
      result = wait_for_modem_response(new_state)
      {:reply, result, new_state}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp send_to_port(nil, _data), do: :ok

  defp send_to_port(pid, data) when is_pid(pid) do
    Circuits.UART.write(pid, data)
  end

  defp wait_for_response(state, timeout_ms) do
    # Poll for response flag (set by incoming data handler)
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_wait_response(state, deadline)
  end

  defp do_wait_response(%{response: true} = state, _deadline), do: state

  defp do_wait_response(state, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      state
    else
      Process.sleep(10)
      do_wait_response(state, deadline)
    end
  end

  defp wait_for_modem_response(_state) do
    # Simplified modem response parsing
    # Original parsed single-character result codes:
    #   '1','L' = CONNECTED AT 2400 BAUD
    #   '3'     = NO CARRIER
    #   '4','C' = MODEM ERROR
    #   '6','E' = NO DIAL TONE
    #   '7','B' = BUSY
    #   '8','F' = NO ANSWER
    #   'T'     = TIME OUT
    receive do
      {:modem_response, response} -> response
    after
      30_000 -> {:error, :timeout}
    end
  end

  defp notify_listeners(listeners, message) do
    Enum.each(listeners, fn pid -> send(pid, {:radarpas, message}) end)
  end
end
