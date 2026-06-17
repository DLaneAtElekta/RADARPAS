defmodule Radarpas.Radar do
  @moduledoc """
  Main radar application logic - command handling and main loops.
  Translated from the Main Routines section of RADAR.PAS (lines 1608-1886).

  The original program had three main loops, each running in a repeat..until:
  - ModemLoop: Idle mode, waiting for user to select/call a station
  - InterLoop: Connected to radar, sending commands and receiving data
  - RxPicLoop: Receiving a radar picture (scan lines arriving via interrupt)

  All three loops shared a common command handler (ExecCom) for graphics
  toggles, and communicated via the global Mode variable and Response flag.

  In Elixir, we model this as a GenServer with the mode as state.
  The interrupt-driven receive (RS232Interupt) is handled by the
  Communication module's GenServer receiving UART messages.

  Original procedures translated:
    ExecCom, RxGraphLoop, RxPicLoop, InterLoop, ModemLoop,
    Initialize, DeInit, Config, main program
  """

  use GenServer
  require Logger

  alias Radarpas.CoreTypes
  alias Radarpas.CoreTypes.{TimeRec, PicRec}
  alias Radarpas.Communication
  alias Radarpas.Graphics
  alias Radarpas.Screen
  alias Radarpas.Pictures
  alias Radarpas.Stations

  # ============================================================================
  # Application State
  # Original global variables spread across the entire program:
  #   Mode, ErrorFlag, GraphicsOn, StationName, Pic[0..100], CurrPic, MaxPic,
  #   RT, HelpOn, Gfx1On, Gfx2On, RngMksOn, DirPath, ModemType, ComPort,
  #   Printer, Clock, PhoneNum, Map1, Map2, OldDir, PictureSaved
  # ============================================================================

  defstruct mode: :modem,
            station: nil,
            pics: [],
            curr_pic: 0,
            max_pic: 0,
            rt: 0,
            screen: %Screen{},
            graphics: %Graphics{},
            dir_path: ".",
            modem_type: 0,
            com_port: "COM1",
            printer: 0,
            clock: 0,
            picture_saved: false,
            renderer: nil

  # ============================================================================
  # Configuration
  # Original: const DirPath, ModemType, ComPort, Printer, Clock (lines 47-52)
  # These were stored as typed constants in the executable and could be
  # modified via the Config procedure which wrote back to RADAR.COM on disk.
  # ============================================================================

  defmodule Config do
    @moduledoc """
    Application configuration.
    Original: procedure Config - lines 1543-1606
    Allowed changing modem type, COM port, clock format, printer type,
    and directory path. Wrote changes directly into the RADAR.COM executable.
    """
    defstruct dir_path: ".",
              modem_type: 0,
              com_port: "/dev/ttyUSB0",
              baud_rate: 2400,
              printer: 0,
              clock: 0
  end

  # ============================================================================
  # GenServer API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialize the application.
  Original: procedure Initialize - lines 1491-1526
  Zeroed all global variables, set up console output redirect,
  initialized EGA mode (640x350x16), set up RS232 interrupt handler,
  enabled IRQ4 on the 8259 PIC, configured modem, and displayed help.
  """
  def initialize(config \\ %Config{}) do
    GenServer.call(__MODULE__, {:initialize, config})
  end

  @doc "Get current state."
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Process a keyboard command."
  def process_key(key) do
    GenServer.call(__MODULE__, {:key, key})
  end

  @doc "Select a station by letter (A-M)."
  def select_station(letter) do
    GenServer.call(__MODULE__, {:select_station, letter})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    state = %__MODULE__{
      dir_path: Keyword.get(opts, :dir_path, "."),
      modem_type: Keyword.get(opts, :modem_type, 0),
      com_port: Keyword.get(opts, :com_port, "/dev/ttyUSB0")
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:initialize, config}, _from, state) do
    # Initialize EGA (generate initial screen commands)
    now = %TimeRec{}
    init_commands = Graphics.init_ega(now)

    # Initialize RS232
    Communication.init_rs232(config.com_port, config.baud_rate)

    # Configure modem
    case config.modem_type do
      0 ->
        # Hayes: AT &F &C1 &D2 L M1 E V X4
        Communication.tx(?A)
        Communication.tx(?T)

      _ ->
        :ok
    end

    new_state = %{
      state
      | dir_path: config.dir_path,
        modem_type: config.modem_type,
        com_port: config.com_port,
        screen: %Screen{help_on: true}
    }

    help_commands = Screen.write_help(new_state.screen, new_state.mode)

    {:reply, {:ok, init_commands ++ help_commands}, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:key, key}, _from, state) do
    {new_state, commands} = handle_key(state, key)
    {:reply, {:ok, commands}, new_state}
  end

  def handle_call({:select_station, letter}, _from, state) do
    stations = Stations.list_stations(state.dir_path)

    case Enum.find(stations, fn {l, _} -> l == letter end) do
      {_, station_name} ->
        # Original: lines 1384-1391
        # Cleared overlays, loaded station, fetched first picture
        case Stations.load_station(state.dir_path, station_name) do
          {:ok, station} ->
            new_state = %{
              state
              | station: station,
                pics: station.pics,
                curr_pic: 0,
                max_pic: station.max_pic,
                screen: %{state.screen | gfx1_on: false, gfx2_on: false, rng_mks_on: false}
            }

            clear_cmds = Graphics.clear_screen(Screen.circle1())
            {:reply, {:ok, clear_cmds}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      nil ->
        {:reply, {:error, :invalid_station}, state}
    end
  end

  @impl true
  def handle_info({:radarpas, {:line_received, line_num, _data}}, state) do
    # Picture line received from Communication module
    if state.mode == :rx_pic and line_num >= 352 do
      # Picture complete
      Logger.info("Picture reception complete")
      Communication.hang_up()
      {:noreply, %{state | mode: :modem, picture_saved: true}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Command Handling
  # Original: procedure ExecCom - lines 1612-1648
  # Processed regular key codes for graphics toggles.
  # Extended (function) keys were handled in each loop's case statement.
  # ============================================================================

  @doc """
  Process a key press and return updated state + drawing commands.
  Original: procedure ExecCom - lines 1612-1648
  """
  def handle_key(state, key) do
    case key do
      # 'G' - Toggle all graphics planes
      # Original: ToggleGraphics (lines 401-405)
      ?G ->
        new_gfx = Graphics.toggle_graphics(state.graphics)
        {%{state | graphics: new_gfx}, []}

      ?g ->
        handle_key(state, ?G)

      # 'R' - Toggle range markers
      # Original: lines 1616-1624
      ?R ->
        new_screen = %{state.screen | rng_mks_on: not state.screen.rng_mks_on}
        commands = if new_screen.rng_mks_on, do: Screen.write_rng_mks(), else: redraw(state)
        {%{state | screen: new_screen}, commands}

      ?r ->
        handle_key(state, ?R)

      # 'H' - Toggle help display
      # Original: lines 1625-1628
      ?H ->
        new_screen = %{state.screen | help_on: not state.screen.help_on}
        commands = Screen.write_help(new_screen, state.mode)
        {%{state | screen: new_screen}, commands}

      ?h ->
        handle_key(state, ?H)

      # '1' - Toggle map overlay 1
      # Original: lines 1629-1636
      ?1 ->
        if state.station != nil do
          new_screen = %{state.screen | gfx1_on: not state.screen.gfx1_on}
          commands = if new_screen.gfx1_on, do: draw_map1(state), else: redraw(state)
          {%{state | screen: new_screen}, commands}
        else
          {state, []}
        end

      # '2' - Toggle map overlay 2
      # Original: lines 1637-1647
      ?2 ->
        if state.station != nil do
          new_screen = %{state.screen | gfx2_on: not state.screen.gfx2_on}
          commands = if new_screen.gfx2_on, do: draw_map2(state), else: redraw(state)
          {%{state | screen: new_screen}, commands}
        else
          {state, []}
        end

      # '+' / '-' - Navigate pictures (Modem mode only)
      # Original: lines 1854-1858
      ?+ ->
        if state.mode == :modem and state.curr_pic < state.max_pic do
          new_state = %{state | curr_pic: state.curr_pic + 1}
          {new_state, fetch_pic_commands(new_state)}
        else
          {state, []}
        end

      ?- ->
        if state.mode == :modem and state.curr_pic > 0 do
          new_state = %{state | curr_pic: state.curr_pic - 1}
          {new_state, fetch_pic_commands(new_state)}
        else
          {state, []}
        end

      # Extended key codes (function keys)
      # Original: Escape flag + key code from ReadKbd
      # F1 (#59) - Select Station (Modem) / Tilt Up (Interactive)
      {:f1} ->
        handle_function_key(state, :f1)

      {:f2} ->
        handle_function_key(state, :f2)

      {:f3} ->
        handle_function_key(state, :f3)

      {:f4} ->
        handle_function_key(state, :f4)

      {:f5} ->
        handle_function_key(state, :f5)

      {:f6} ->
        handle_function_key(state, :f6)

      {:f7} ->
        handle_function_key(state, :f7)

      # ESC - Context-dependent quit/disconnect
      # Original: lines 1818, 1860
      27 ->
        handle_escape(state)

      _ ->
        {state, []}
    end
  end

  # ============================================================================
  # Function Key Handlers
  # Original: extended key dispatch in ModemLoop (lines 1839-1851)
  #           and InterLoop (lines 1789-1817)
  # ============================================================================

  defp handle_function_key(state, key) do
    case {state.mode, key} do
      # Modem mode function keys
      # F1 = Select Station, F2 = Call Station, F3 = Storage
      {:modem, :f1} ->
        # Would open station selection UI
        {state, [{:draw_text, 0, 0, "Select Station..."}]}

      {:modem, :f2} ->
        # Call station
        if state.station != nil do
          call_current_station(state)
        else
          {state, []}
        end

      {:modem, :f3} ->
        # Open storage/picture browser
        {state, [{:draw_text, 0, 0, "Storage..."}]}

      # Interactive mode function keys
      # F1 = Tilt Up, F2 = Tilt Down, F3 = Range Up, F4 = Range Down
      # F5 = Gain Up, F6 = Gain Down, F7 = Request Picture
      # Original: lines 1791-1816
      {:interactive, :f1} ->
        Communication.send_com(CoreTypes.tilt_up(), 150)
        {state, []}

      {:interactive, :f2} ->
        Communication.send_com(CoreTypes.tilt_down(), 150)
        {state, []}

      {:interactive, :f3} ->
        Communication.send_com(CoreTypes.range_up(), 300)
        commands = redraw(state)
        {state, commands}

      {:interactive, :f4} ->
        Communication.send_com(CoreTypes.range_down(), 300)
        commands = redraw(state)
        {state, commands}

      {:interactive, :f5} ->
        Communication.send_com(CoreTypes.gain_up(), 150)
        {state, []}

      {:interactive, :f6} ->
        Communication.send_com(CoreTypes.gain_down(), 150)
        {state, []}

      {:interactive, :f7} ->
        # Request picture - enter RxPicLoop
        start_rx_pic(state)

      _ ->
        {state, []}
    end
  end

  # ============================================================================
  # InterLoop - Interactive mode
  # Original: procedure InterLoop - lines 1764-1833
  # Connected to radar, probed with 'X' command (up to 4 retries),
  # checked for map overlay updates, then entered command loop.
  # ============================================================================

  defp call_current_station(state) do
    case Communication.call_station(state.station.phone, state.modem_type) do
      {:ok, _} ->
        # Transition to interactive mode
        # Original: lines 1767-1782 - sent 'X' probe up to 4 times
        new_state = %{state | mode: :interactive}
        commands = Screen.write_help(new_state.screen, :interactive)
        {new_state, commands}

      {:error, reason} ->
        {state, [Graphics.gr_message("CALL FAILED: #{inspect(reason)}")]}
    end
  end

  # ============================================================================
  # RxPicLoop - Picture reception
  # Original: procedure RxPicLoop - lines 1689-1761
  # Sent SendPic command, cleared screen, drew scale, waited for picture
  # start sequence ($FF,$FE,$FD), then displayed scan lines in real-time
  # as they arrived via the interrupt handler. Could be aborted with ESC.
  # ============================================================================

  defp start_rx_pic(state) do
    Communication.send_com(CoreTypes.send_pic(), 200)

    new_state = %{
      state
      | mode: :wait_pic,
        picture_saved: false,
        curr_pic: state.max_pic + 1
    }

    commands =
      Graphics.clear_screen(Screen.circle1()) ++
        Graphics.draw_scale() ++
        [Graphics.gr_message("WAITING FOR PICTURE")]

    Communication.subscribe()
    {new_state, commands}
  end

  # ============================================================================
  # Escape Handler
  # Original: ESC handling varied by mode
  # Modem: "QUIT PROGRAM?" (line 1860)
  # Interactive: "DISCONNECT STATION?" (line 1818)
  # RxPic: "ABORT PICTURE?" (line 1706)
  # ============================================================================

  defp handle_escape(%{mode: :modem} = state) do
    {state, [Graphics.gr_message("QUIT PROGRAM? (Y/N)")]}
  end

  defp handle_escape(%{mode: :interactive} = state) do
    Communication.hang_up()
    new_state = %{state | mode: :modem}
    commands = Screen.write_help(new_state.screen, :modem)
    {new_state, commands}
  end

  defp handle_escape(%{mode: mode} = state) when mode in [:rx_pic, :wait_pic] do
    # Abort picture reception
    Communication.tx(?Y)
    Communication.tx(?Y)
    new_state = %{state | mode: :interactive}
    {new_state, [Graphics.gr_message("PICTURE ABORTED")]}
  end

  defp handle_escape(state), do: {state, []}

  # ============================================================================
  # Helpers
  # ============================================================================

  defp redraw(state) do
    clear = Graphics.clear_screen(Screen.circle1())

    gfx1 =
      if state.screen.gfx1_on and state.station != nil do
        pic = current_pic(state)
        if pic, do: Screen.write_gfx(state.station.map1.landmarks, state.station.map1.segments, pic), else: []
      else
        []
      end

    gfx2 =
      if state.screen.gfx2_on and state.station != nil do
        pic = current_pic(state)
        if pic, do: Screen.write_gfx(state.station.map2.landmarks, state.station.map2.segments, pic), else: []
      else
        []
      end

    rng = if state.screen.rng_mks_on, do: Screen.write_rng_mks(), else: []

    clear ++ gfx1 ++ gfx2 ++ rng
  end

  defp draw_map1(state) do
    if state.station != nil do
      pic = current_pic(state) || %PicRec{}
      Screen.write_gfx(state.station.map1.landmarks, state.station.map1.segments, pic)
    else
      []
    end
  end

  defp draw_map2(state) do
    if state.station != nil do
      pic = current_pic(state) || %PicRec{}
      Screen.write_gfx(state.station.map2.landmarks, state.station.map2.segments, pic)
    else
      []
    end
  end

  defp current_pic(state) do
    if state.curr_pic > 0 and state.curr_pic <= length(state.pics) do
      Enum.at(state.pics, state.curr_pic - 1)
    else
      nil
    end
  end

  defp fetch_pic_commands(state) do
    pic = current_pic(state)

    if pic do
      params_cmds = Screen.write_params(pic, state.rt, state.mode)
      params_cmds
    else
      Screen.write_params(nil, state.rt, state.mode)
    end
  end
end
