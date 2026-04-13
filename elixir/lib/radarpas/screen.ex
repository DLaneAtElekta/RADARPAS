defmodule Radarpas.Screen do
  @moduledoc """
  Screen format routines - radar display overlays and UI.
  Translated from the Screen Format Routines section of RADAR.PAS (lines 514-825).

  Original procedures translated:
    WriteRngMks, WriteGfx, WriteHelp, WriteParams, ClearScreen, UnWindow, IOError

  The original code used precomputed circle lookup tables (Circle1..Circle5) to
  draw range marker rings without trigonometry, and ASin/ACos tables for map
  overlay coordinate conversion - all optimized for the 8088 processor.
  """

  alias Radarpas.CoreTypes
  alias Radarpas.CoreTypes.{TimeRec, PicRec}
  alias Radarpas.Graphics

  # ============================================================================
  # Screen State
  # Original global variables: HelpOn, Gfx1On, Gfx2On, RngMksOn, RngChng
  # ============================================================================

  defstruct help_on: true,
            gfx1_on: false,
            gfx2_on: false,
            rng_mks_on: false

  # ============================================================================
  # Circle Lookup Tables
  # Original: Circle1..Circle5 - precomputed Y-to-X coordinate tables
  # for drawing concentric range marker rings.
  # Circle1 = outermost ring (radius ~255 at equator)
  # Circle5 = innermost ring (radius ~51 at equator)
  # These were computed offline for the 640x350 EGA aspect ratio.
  # ============================================================================

  @circle1 [
    92, 96, 99, 102, 105, 108, 111, 114, 117, 119, 122, 124, 127, 129, 131, 134,
    136, 138, 140, 142, 144, 146, 148, 150, 152, 154, 156, 157, 159, 161, 162, 164,
    166, 167, 169, 170, 172, 173, 175, 176, 178, 179, 181, 182, 183, 185, 186, 187,
    188, 190, 191, 192, 193, 194, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205,
    206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 217, 218, 219, 220,
    221, 221, 222, 223, 224, 225, 225, 226, 227, 227, 228, 229, 229, 230, 231, 231,
    232, 233, 233, 234, 235, 235, 236, 236, 237, 237, 238, 238, 239, 239, 240, 240,
    241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 245, 246, 246, 247, 247, 247,
    248, 248, 248, 249, 249, 249, 250, 250, 250, 250, 251, 251, 251, 251, 252, 252,
    252, 252, 253, 253, 253, 253, 253, 254, 254, 254, 254, 254, 254, 254, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
  ]

  @circle2 List.duplicate(0, 25) ++
             [
               0, 20, 31, 39, 45, 51, 56, 60, 64, 68, 72, 76, 79, 82, 85, 88, 91,
               94, 96, 99, 101, 103, 106, 108, 110, 112, 114, 116, 118, 120, 122,
               124, 125, 127, 129, 131, 132, 134, 135, 137, 138, 140, 141, 143, 144,
               145, 147, 148, 149, 151, 152, 153, 154, 155, 156, 158, 159, 160, 161,
               162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 171, 172, 173, 174,
               175, 176, 176, 177, 178, 179, 180, 180, 181, 182, 182, 183, 184, 184,
               185, 186, 186, 187, 187, 188, 188, 189, 190, 190, 191, 191, 192, 192,
               193, 193, 194, 194, 194, 195, 195, 196, 196, 196, 197, 197, 197, 198,
               198, 198, 199, 199, 199, 200, 200, 200, 200, 201, 201, 201, 201, 201,
               202, 202, 202, 202, 202, 202, 203, 203, 203, 203, 203, 203, 203, 203,
               203, 203, 203, 203, 203, 203, 204, 204
             ]

  @circle3 List.duplicate(0, 62) ++
             [
               0, 15, 25, 32, 38, 43, 47, 51, 55, 58, 61, 64, 67, 70, 73, 75, 77,
               80, 82, 84, 86, 88, 90, 92, 94, 95, 97, 99, 100, 102, 103, 105, 106,
               108, 109, 110, 112, 113, 114, 115, 116, 118, 119, 120, 121, 122, 123,
               124, 125, 126, 127, 128, 128, 129, 130, 131, 132, 133, 133, 134, 135,
               136, 136, 137, 138, 138, 139, 140, 140, 141, 141, 142, 142, 143, 143,
               144, 144, 145, 145, 146, 146, 146, 147, 147, 148, 148, 148, 149, 149,
               149, 149, 150, 150, 150, 150, 151, 151, 151, 151, 151, 152, 152, 152,
               152, 152, 152, 152, 152, 152, 152, 152, 152, 153, 153
             ]

  @circle4 List.duplicate(0, 99) ++
             [
               0, 10, 19, 25, 30, 34, 38, 41, 44, 47, 49, 51, 54, 56, 58, 60, 62,
               63, 65, 67, 68, 70, 71, 72, 74, 75, 76, 77, 79, 80, 81, 82, 83, 84,
               85, 85, 86, 87, 88, 89, 90, 90, 91, 92, 92, 93, 93, 94, 95, 95, 96,
               96, 97, 97, 97, 98, 98, 98, 99, 99, 99, 100, 100, 100, 100, 101, 101,
               101, 101, 101, 101, 101, 101, 101, 101, 102, 102
             ]

  @circle5 List.duplicate(0, 136) ++
             [
               0, 5, 12, 17, 20, 23, 25, 28, 30, 31, 33, 35, 36, 37, 38, 40, 41,
               42, 42, 43, 44, 45, 46, 46, 47, 47, 48, 48, 49, 49, 49, 50, 50, 50,
               50, 50, 50, 50, 51, 51
             ]

  # ASin/ACos lookup tables for map coordinate conversion
  # Original: ASin: array[0..360] of byte; ACos: array[0..360] of byte
  # These map bearing (0-360 degrees) to pixel offsets centered at 128.
  @a_sin [
    128, 128, 128, 129, 129, 130, 130, 131, 131, 132, 132, 132, 133, 133, 134, 134,
    135, 135, 135, 136, 136, 137, 137, 138, 138, 138, 139, 139, 140, 140, 140, 141,
    141, 141, 142, 142, 143, 143, 143, 144, 144, 144, 145, 145, 145, 146, 146, 146,
    147, 147, 147, 147, 148, 148, 148, 148, 149, 149, 149, 149, 150, 150, 150, 150,
    151, 151, 151, 151, 151, 151, 152, 152, 152, 152, 152, 152, 152, 152, 153, 153,
    153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153,
    153, 153, 153, 153, 153, 153, 153, 152, 152, 152, 152, 152, 152, 152, 152, 151,
    151, 151, 151, 151, 151, 150, 150, 150, 150, 149, 149, 149, 149, 148, 148, 148,
    148, 147, 147, 147, 147, 146, 146, 146, 145, 145, 145, 144, 144, 144, 143, 143,
    143, 142, 142, 141, 141, 141, 140, 140, 140, 139, 139, 138, 138, 138, 137, 137,
    136, 136, 135, 135, 135, 134, 134, 133, 133, 132, 132, 132, 131, 131, 130, 130,
    129, 129, 128, 128, 128, 128, 128, 127, 127, 126, 126, 125, 125, 124, 124, 124,
    123, 123, 122, 122, 121, 121, 121, 120, 120, 119, 119, 118, 118, 118, 117, 117,
    116, 116, 116, 115, 115, 115, 114, 114, 113, 113, 113, 112, 112, 112, 111, 111,
    111, 110, 110, 110, 109, 109, 109, 109, 108, 108, 108, 108, 107, 107, 107, 107,
    106, 106, 106, 106, 105, 105, 105, 105, 105, 105, 104, 104, 104, 104, 104, 104,
    104, 104, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103,
    103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 104, 104, 104, 104, 104,
    104, 104, 104, 105, 105, 105, 105, 105, 105, 106, 106, 106, 106, 107, 107, 107,
    107, 108, 108, 108, 108, 109, 109, 109, 109, 110, 110, 110, 111, 111, 111, 112,
    112, 112, 113, 113, 113, 114, 114, 115, 115, 115, 116, 116, 116, 117, 117, 118,
    118, 118, 119, 119, 120, 120, 121, 121, 121, 122, 122, 123, 123, 124, 124, 124,
    125, 125, 126, 126, 127, 127, 128, 128, 128
  ]

  @a_cos [
    146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146, 146,
    145, 145, 145, 145, 145, 145, 145, 145, 145, 144, 144, 144, 144, 144, 144, 144,
    143, 143, 143, 143, 143, 142, 142, 142, 142, 142, 141, 141, 141, 141, 140, 140,
    140, 140, 139, 139, 139, 139, 138, 138, 138, 138, 137, 137, 137, 137, 136, 136,
    136, 135, 135, 135, 134, 134, 134, 134, 133, 133, 133, 132, 132, 132, 131, 131,
    131, 130, 130, 130, 129, 129, 129, 128, 128, 128, 128, 128, 128, 128, 127, 127,
    127, 126, 126, 126, 125, 125, 125, 124, 124, 124, 123, 123, 123, 122, 122, 122,
    122, 121, 121, 121, 120, 120, 120, 119, 119, 119, 119, 118, 118, 118, 118, 117,
    117, 117, 117, 116, 116, 116, 116, 115, 115, 115, 115, 114, 114, 114, 114, 114,
    113, 113, 113, 113, 113, 113, 112, 112, 112, 112, 112, 112, 111, 111, 111, 111,
    111, 111, 111, 111, 111, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110,
    110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110, 110,
    110, 110, 110, 110, 111, 111, 111, 111, 111, 111, 111, 111, 111, 112, 112, 112,
    112, 112, 112, 112, 113, 113, 113, 113, 113, 114, 114, 114, 114, 114, 115, 115,
    115, 115, 116, 116, 116, 116, 116, 117, 117, 117, 118, 118, 118, 118, 119, 119,
    119, 119, 120, 120, 120, 121, 121, 121, 122, 122, 122, 122, 123, 123, 123, 124,
    124, 124, 125, 125, 125, 126, 126, 126, 127, 127, 127, 128, 128, 128, 128, 128,
    128, 128, 129, 129, 129, 130, 130, 130, 131, 131, 131, 132, 132, 132, 133, 133,
    133, 134, 134, 134, 134, 135, 135, 135, 136, 136, 136, 137, 137, 137, 137, 138,
    138, 138, 138, 139, 139, 139, 139, 140, 140, 140, 140, 141, 141, 141, 141, 142,
    142, 142, 142, 142, 143, 143, 143, 143, 143, 143, 144, 144, 144, 144, 144, 144,
    145, 145, 145, 145, 145, 145, 145, 145, 145, 146, 146, 146, 146, 146, 146, 146,
    146, 146, 146, 146, 146, 146, 146, 146, 146
  ]

  def circle1, do: @circle1
  def a_sin, do: @a_sin
  def a_cos, do: @a_cos

  # ============================================================================
  # Range Markers
  # Original: procedure WriteRngMks - lines 570-603
  # Drew 5 concentric circles using the precomputed lookup tables.
  # For each Y from 175 downto 1, plotted points on all circles by
  # iterating from circle[i-1] to circle[i] and mirroring across
  # both X and Y axes around center (320, 175).
  # ============================================================================

  @doc """
  Generate range marker circle drawing commands.
  Original: procedure WriteRngMks - lines 570-603
  """
  def write_rng_mks do
    circles = [
      {0, @circle1},
      {25, @circle2},
      {62, @circle3},
      {99, @circle4},
      {136, @circle5}
    ]

    for i <- 175..1//-1, {min_i, circle} <- circles, i > min_i do
      prev = Enum.at(circle, i - 1, 0)
      curr = Enum.at(circle, i, 0)

      for j <- prev..curr do
        [
          Graphics.plot(320 + j, i),
          Graphics.plot(320 - j, i),
          Graphics.plot(320 + j, 350 - i),
          Graphics.plot(320 - j, 350 - i)
        ]
      end
    end
    |> List.flatten()
  end

  # ============================================================================
  # Map Overlay
  # Original: procedure WriteGfx(var At) - lines 647-705
  # Rendered map data (landmarks and coastline segments) using the ASin/ACos
  # tables to convert polar coordinates (bearing, range) to screen coordinates.
  # The data format alternated between landmarks (name + position) and
  # line segments (two endpoints), terminated by zero records.
  # ============================================================================

  @doc """
  Landmark record for map overlays.
  Original: LandMarkRec = record Bear, Range: integer; Name: array[1..3] of char; end
  """
  defmodule Landmark do
    defstruct bearing: 0, range: 0, name: "   "
  end

  @doc """
  Segment record for coastline/boundary drawing.
  Original: SegmentRec = record Range1, Bear1, Range2, Bear2: integer; end
  """
  defmodule Segment do
    defstruct range1: 0, bearing1: 0, range2: 0, bearing2: 0
  end

  @doc """
  Generate map overlay drawing commands from landmark and segment data.
  Original: procedure WriteGfx(var At) - lines 647-705
  Used ASin/ACos lookup tables to convert polar to screen coordinates.
  """
  def write_gfx(landmarks, segments, %PicRec{} = pic) do
    max_range = CoreTypes.range_val(pic.range) * 10
    min_range = div(max_range, 7)
    adj = CoreTypes.range_val(pic.range)

    landmark_cmds =
      landmarks
      |> Enum.filter(fn lm -> lm.range > min_range and lm.range < max_range end)
      |> Enum.map(fn lm ->
        a_sin_val = Enum.at(@a_sin, lm.bearing, 128)
        a_cos_val = Enum.at(@a_cos, lm.bearing, 128)

        {x, y} =
          if lm.range > 1310 do
            {300 + trunc(lm.range * (a_sin_val - 128.0) / adj),
             170 - trunc(lm.range * (a_cos_val - 128.0) / adj)}
          else
            {300 + div(lm.range * (a_sin_val - 128), adj),
             170 - div(lm.range * (a_cos_val - 128), adj)}
          end

        Graphics.gr_write(" #{lm.name} ", x, y)
      end)

    segment_cmds =
      segments
      |> Enum.filter(fn seg -> seg.range1 < max_range and seg.range2 < max_range end)
      |> Enum.map(fn seg ->
        a_sin1 = Enum.at(@a_sin, seg.bearing1, 128)
        a_cos1 = Enum.at(@a_cos, seg.bearing1, 128)
        a_sin2 = Enum.at(@a_sin, seg.bearing2, 128)
        a_cos2 = Enum.at(@a_cos, seg.bearing2, 128)

        {x1, y1, x2, y2} =
          if seg.range1 > 1310 or seg.range2 > 1310 do
            {320 + trunc(seg.range1 * (a_sin1 - 128.0) / adj),
             174 - trunc(seg.range1 * (a_cos1 - 128.0) / adj),
             320 + trunc(seg.range2 * (a_sin2 - 128.0) / adj),
             174 - trunc(seg.range2 * (a_cos2 - 128.0) / adj)}
          else
            {div(seg.range1 * (a_sin1 - 128), adj) + 320,
             174 - div(seg.range1 * (a_cos1 - 128), adj),
             div(seg.range2 * (a_sin2 - 128), adj) + 320,
             174 - div(seg.range2 * (a_cos2 - 128), adj)}
          end

        Graphics.line(x1, y1, x2, y2)
      end)

    landmark_cmds ++ segment_cmds
  end

  # ============================================================================
  # Help Screen
  # Original: procedure WriteHelp - lines 707-757
  # Displayed context-sensitive help text based on the current operating mode.
  # ============================================================================

  @doc """
  Generate help screen drawing commands.
  Original: procedure WriteHelp - lines 707-757
  """
  def write_help(%__MODULE__{help_on: true}, mode) do
    mode_help =
      case mode do
        :modem ->
          [
            {:draw_text, 0, 2, "F1\xB3Select Station"},
            {:draw_text, 0, 3, "F2\xB3Call Station"},
            {:draw_text, 0, 4, "F3\xB3Storage"},
            {:draw_text, 0, 19, "+ Next Pic"},
            {:draw_text, 0, 20, "- Prev Pic"},
            {:draw_text, 0, 21, "ESC\xB3Quit"}
          ]

        :interactive ->
          [
            {:draw_text, 0, 21, "ESC\xB3Disconnect"}
          ]

        :rx_pic ->
          [
            {:draw_text, 0, 21, "ESC\xB3Abort"}
          ]

        _ ->
          []
      end

    graphics_help = [
      {:draw_text, 66, 2, "G\xB3All Graphics"},
      {:draw_text, 67, 3, "R\xB3Range Marks"},
      {:draw_text, 73, 4, "1\xB3Map 1"},
      {:draw_text, 73, 5, "2\xB3Map 2"}
    ]

    mode_help ++ graphics_help
  end

  def write_help(%__MODULE__{help_on: false}, _mode) do
    # Clear help area
    [
      {:draw_text, 66, 2, "              "},
      {:draw_text, 67, 3, "             "},
      {:draw_text, 73, 4, "       "},
      {:draw_text, 73, 5, "       "}
    ]
  end

  # ============================================================================
  # Parameter Display
  # Original: procedure WriteParams - lines 759-781
  # Showed current radar parameters (tilt, time, range, gain) and RT status.
  # ============================================================================

  @doc """
  Generate parameter display drawing commands.
  Original: procedure WriteParams - lines 759-781
  """
  def write_params(%PicRec{} = pic, rt, mode) do
    tilt_str = String.pad_leading("#{CoreTypes.tilt_val(pic.tilt)}", 3)
    range_str = String.pad_leading("#{CoreTypes.range_val(pic.range)}", 3)

    gain_str =
      if pic.gain < 17,
        do: String.pad_leading("#{pic.gain}", 4),
        else: " PRE"

    time_str = format_time_display(pic.time)

    rt_cmd =
      if mode == :interactive do
        rt_text =
          case rt do
            0 -> " RT OFF "
            _ -> " RT ON  "
          end

        [{:draw_text, 36, 0, rt_text}]
      else
        []
      end

    [
      {:draw_text, 8, 0, tilt_str},
      {:draw_text, 72, 0, time_str},
      {:draw_text, 8, 24, range_str},
      {:draw_text, 72, 24, gain_str}
    ] ++ rt_cmd
  end

  def write_params(nil, _rt, _mode) do
    [
      {:draw_text, 8, 0, "XXX"},
      {:draw_text, 72, 0, "XX:XX  "},
      {:draw_text, 8, 24, "XXX"},
      {:draw_text, 72, 24, " XXX"}
    ]
  end

  defp format_time_display(%TimeRec{hour: h, minute: m}) do
    h_display = if h < 13, do: h, else: h - 12
    m_str = String.pad_leading("#{m}", 2, "0")
    suffix = if h > 12, do: "pm", else: "am"
    "#{String.pad_leading("#{h_display}", 2)}:#{m_str}#{suffix}"
  end

  # ============================================================================
  # UnWindow - restore display after popup menus
  # Original: procedure UnWindow - lines 794-801
  # ============================================================================

  @doc """
  Restore the screen after a popup window was displayed.
  Original: procedure UnWindow - lines 794-801
  Cleared planes [2,3], re-drew active map overlays and range markers.
  """
  def un_window(%__MODULE__{} = state, map1, map2, pic) do
    clear_cmds = Graphics.clear_screen(Radarpas.Screen.circle1())

    gfx1_cmds = if state.gfx1_on, do: write_gfx(map1.landmarks, map1.segments, pic), else: []
    gfx2_cmds = if state.gfx2_on, do: write_gfx(map2.landmarks, map2.segments, pic), else: []
    rng_cmds = if state.rng_mks_on, do: write_rng_mks(), else: []

    clear_cmds ++ gfx1_cmds ++ gfx2_cmds ++ rng_cmds
  end
end
