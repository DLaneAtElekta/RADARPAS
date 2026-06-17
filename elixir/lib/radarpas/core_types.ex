defmodule Radarpas.CoreTypes do
  @moduledoc """
  Core types for RADARPAS - translated from the original Turbo Pascal RADAR.PAS (1988).

  Original Pascal type definitions (lines 17-103):
    TiltType    = 0..11
    RangeType   = 0..4
    GainType    = 1..17
    ModeType    = (Modem, Interactive, WaitPic, RxPic, RxGraph)
    TimeRec     = record Year, Month, Day, Hour, Minute end
    PicRec      = record FileName, FileDate, FileTime, Time, Tilt, Range, Gain end
  """

  # ============================================================================
  # Operating mode enumeration
  # Original: ModeType = (Modem, Interactive, WaitPic, RxPic, RxGraph)
  # ============================================================================

  @type mode :: :modem | :interactive | :wait_pic | :rx_pic | :rx_graph

  # ============================================================================
  # Time record
  # Original: TimeRec = record Year: 1980..2099; Month: 1..12; Day: 1..31;
  #                             Hour: 0..23; Minute: 0..59; end
  # ============================================================================

  @type time_rec :: %{
          year: 1980..2099,
          month: 1..12,
          day: 1..31,
          hour: 0..23,
          minute: 0..59
        }

  defmodule TimeRec do
    @moduledoc "Time record - matches Pascal TimeRec exactly."
    defstruct year: 1988, month: 1, day: 1, hour: 0, minute: 0

    @doc "Create a zero/default time."
    def zero, do: %__MODULE__{}
  end

  # ============================================================================
  # Picture record
  # Original: PicRec = record
  #   FileName: string[12]; FileDate, FileTime: integer;
  #   Time: TimeRec; Tilt: TiltType; Range: RangeType; Gain: GainType; end
  # ============================================================================

  defmodule PicRec do
    @moduledoc """
    Picture metadata record - matches Pascal PicRec exactly.
    Original: lines 71-79 of RADAR.PAS
    """
    defstruct file_name: "",
              file_date: 0,
              file_time: 0,
              time: %TimeRec{},
              tilt: 0,
              range: 0,
              gain: 1

    @doc """
    Generate filename for a picture.
    Original: SavePic procedure (lines 1127-1146)
    Format: HHMM<tilt><range><gain>.PIC
    where tilt = Chr(Tilt+65), range = Chr(Range+65), gain = Chr(Gain+64)
    """
    def generate_file_name(%__MODULE__{} = pic) do
      h1 = div(pic.time.hour, 10) + 48
      h2 = rem(pic.time.hour, 10) + 48
      m1 = div(pic.time.minute, 10) + 48
      m2 = rem(pic.time.minute, 10) + 48
      tilt_char = pic.tilt + 65
      range_char = pic.range + 65
      gain_char = pic.gain + 64

      <<h1, h2, m1, m2, tilt_char, range_char, gain_char>> <> ".PIC"
    end

    @doc """
    Parse filename to extract picture parameters.
    Original: LoadStation procedure (lines 1240-1248)
    """
    def parse_file_name(name) when is_binary(name) and byte_size(name) >= 7 do
      <<h1, h2, m1, m2, tilt_char, range_char, gain_char, _rest::binary>> = name
      hour = (h1 - 48) * 10 + (h2 - 48)
      minute = (m1 - 48) * 10 + (m2 - 48)
      tilt = tilt_char - 65
      range = range_char - 65
      gain = gain_char - 64

      if valid_tilt?(tilt) and valid_range?(range) and valid_gain?(gain) and
           hour in 0..23 and minute in 0..59 do
        {:ok,
         %__MODULE__{
           file_name: name,
           time: %TimeRec{hour: hour, minute: minute},
           tilt: tilt,
           range: range,
           gain: gain
         }}
      else
        {:error, "Invalid parameters in filename"}
      end
    end

    def parse_file_name(_), do: {:error, "Filename too short"}
  end

  # ============================================================================
  # Register type (CPU registers for DOS interrupt calls)
  # Original: RegisterType = record AX,BX,CX,DX,BP,DI,SI,DS,ES,Flags: integer end
  # In Elixir, this is abstracted away - no direct hardware access needed.
  # ============================================================================

  # ============================================================================
  # Constants
  # Original: lines 47-67 of RADAR.PAS
  # ============================================================================

  # Radar command bytes
  # Original: OnOff = #1; SendPic = #4; CheckGraph = #16; SendGraph = #10;
  #           TiltUp = #2; TiltDown = #5; RangeUp = #3; RangeDown = #6;
  #           GainUp = #13; GainDown = #14;
  @on_off 0x01
  @send_pic 0x04
  @check_graph 0x10
  @send_graph 0x0A
  @tilt_up 0x02
  @tilt_down 0x05
  @range_up 0x03
  @range_down 0x06
  @gain_up 0x0D
  @gain_down 0x0E

  def on_off, do: @on_off
  def send_pic, do: @send_pic
  def check_graph, do: @check_graph
  def send_graph, do: @send_graph
  def tilt_up, do: @tilt_up
  def tilt_down, do: @tilt_down
  def range_up, do: @range_up
  def range_down, do: @range_down
  def gain_up, do: @gain_up
  def gain_down, do: @gain_down

  # Tilt values lookup table
  # Original: TiltVal: array[TiltType] of byte = (0,1,2,3,4,5,6,8,10,12,15,20)
  @tilt_val {0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20}

  @doc "Get the display value for a tilt index (0..11)."
  def tilt_val(index) when index in 0..11, do: elem(@tilt_val, index)

  # Range values lookup table
  # Original: RangeVal: array[RangeType] of byte = (10,25,50,100,200)
  @range_val {10, 25, 50, 100, 200}

  @doc "Get the display value for a range index (0..4)."
  def range_val(index) when index in 0..4, do: elem(@range_val, index)

  # Validation helpers
  @doc "Check if a tilt index is valid (0..11)."
  def valid_tilt?(t), do: is_integer(t) and t >= 0 and t <= 11

  @doc "Check if a range index is valid (0..4)."
  def valid_range?(r), do: is_integer(r) and r >= 0 and r <= 4

  @doc "Check if a gain value is valid (1..17)."
  def valid_gain?(g), do: is_integer(g) and g >= 1 and g <= 17

  # EGA palette colors
  # Original: Colors: array[0..15] of byte = ($00,36,50,54,$3F,...,$09,...,$09)
  @colors {0x00, 36, 50, 54, 0x3F, 0x3F, 0x3F, 0x3F,
           0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x09, 0x09}

  @doc "Get EGA palette color value for index 0..15."
  def color(index) when index in 0..15, do: elem(@colors, index)
end
