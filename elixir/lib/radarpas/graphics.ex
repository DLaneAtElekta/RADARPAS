defmodule Radarpas.Graphics do
  @moduledoc """
  Graphics module - Drawing primitives and screen management.
  Translated from the Graphics Routines section of RADAR.PAS (lines 181-508).

  The original code directly manipulated EGA video memory at segment $A000
  using plane selection via ports $3C4/$3C5 and function selection via $3CE/$3CF.
  This translation abstracts the rendering into drawing commands that can be
  executed by any renderer (terminal, GUI, etc.).

  Original procedures translated:
    SelectPlane, ShowPlane, SelectFunc, SetMask, GotoXY, ConOut, ReadStr,
    GRWrite, GRPlot, GRLine, Window, GRMessage, Ask, ToggleGraphics,
    DispLine, DrawScale, InitEGA
  """

  alias Radarpas.CoreTypes.TimeRec

  # ============================================================================
  # Graphics State
  # Original global variables: CurrPlane, CurrFunc, CurrMask, CursX, CursY,
  #   XPos, YPos, XMax, YMax, CharSize, GraphicsOn, LastMess
  # ============================================================================

  defstruct curr_plane: MapSet.new([0, 1, 2, 3]),
            curr_func: :clear,
            curr_mask: 0xFF,
            curs_x: 0,
            curs_y: 0,
            x_pos: 0,
            y_pos: 0,
            x_max: 79,
            y_max: 24,
            char_size: 14,
            graphics_on: true,
            last_mess: ""

  @type plane_set :: MapSet.t()

  # Original: FuncType = (Rot1,Rot2,Rot3,Rot4,Rot5,Rot6,Rot7,_Clr,_And,_Or,_Xor)
  @type func_type :: :rot1 | :rot2 | :rot3 | :rot4 | :rot5 | :rot6 | :rot7 |
                     :clear | :band | :bor | :bxor

  @type draw_command ::
          {:set_pixel, x :: integer(), y :: integer()}
          | {:draw_line, x1 :: integer(), y1 :: integer(), x2 :: integer(), y2 :: integer()}
          | {:fill_rect, x :: integer(), y :: integer(), width :: integer(), height :: integer(),
             value :: byte()}
          | {:draw_text, x :: integer(), y :: integer(), text :: String.t()}
          | {:clear_area, x :: integer(), y :: integer(), width :: integer(), height :: integer()}
          | {:set_planes, plane_set()}
          | {:set_func, func_type()}

  # ============================================================================
  # State Transformations
  # ============================================================================

  @doc """
  Select active write plane(s).
  Original: procedure SelectPlane(ForPlanes: PlaneSet) - lines 199-204
  In the original, this wrote directly to EGA sequencer port $3C4/$3C5.
  """
  def select_plane(%__MODULE__{} = state, planes) do
    %{state | curr_plane: MapSet.new(List.wrap(planes))}
  end

  @doc """
  Select graphics function (write mode).
  Original: procedure SelectFunc(ForFunc: FuncType) - lines 219-225
  Wrote to EGA graphics controller port $3CE/$3CF.
  """
  def select_func(%__MODULE__{} = state, func) do
    %{state | curr_func: func}
  end

  @doc """
  Set bit mask for pixel operations.
  Original: procedure SetMask(ToMask: byte) - lines 228-232
  """
  def set_mask(%__MODULE__{} = state, mask) do
    %{state | curr_mask: mask}
  end

  @doc """
  Move cursor to position.
  Original: procedure GotoXY(X,Y: integer) - lines 241-244
  """
  def goto_xy(%__MODULE__{} = state, x, y) do
    %{state | curs_x: x, curs_y: y}
  end

  @doc """
  Set up a text window region.
  Original: procedure Window(X,Y,XSize,YSize: byte) - lines 350-363
  Cleared the window area in EGA memory and set position/size limits.
  """
  def window(%__MODULE__{} = state, x, y, x_size, y_size) do
    %{state | x_pos: x, y_pos: y, x_max: x_size, y_max: y_size, curs_x: 0, curs_y: 0}
  end

  @doc """
  Toggle between text and graphics display mode.
  Original: procedure ToggleGraphics - lines 401-405
  Toggled EGA planes [0,1] vs [0..3] via ShowPlane.
  """
  def toggle_graphics(%__MODULE__{} = state) do
    %{state | graphics_on: not state.graphics_on}
  end

  # ============================================================================
  # Drawing Commands (Pure - generate command lists)
  # ============================================================================

  @doc """
  Plot a single pixel.
  Original: procedure GRPlot(X,Y: integer) - lines 311-322
  Calculated byte position as Y*80+(X shr 3), bit as $80 shr (X and $07),
  then read-modify-wrote to EGA memory at $A000.
  """
  def plot(x, y) when is_integer(x) and is_integer(y) do
    {:set_pixel, x, y}
  end

  @doc """
  Draw a line between two points.
  Original: procedure GRLine(X1,Y1,X2,Y2: integer) - lines 324-348
  Used a simple DDA (Digital Differential Analyzer) algorithm:
  - If |dy| > |dx|: step along Y, interpolate X as real
  - Otherwise: step along X, interpolate Y as real
  """
  def line(x1, y1, x2, y2) do
    {:draw_line, x1, y1, x2, y2}
  end

  @doc """
  Generate the individual pixel commands for a line (DDA algorithm).
  This is a faithful translation of the original GRLine procedure.
  """
  def line_points(x1, y1, x2, y2) do
    dx = x2 - x1
    dy = y2 - y1

    if abs(dy) > abs(dx) do
      # Step along Y axis
      add = dx / abs(dy)
      dir = if y2 > y1, do: 1, else: -1
      do_line_y(x1 + 0.0, y1, y2, add, dir, [])
    else
      # Step along X axis
      add = if x2 != x1, do: dy / abs(dx), else: 0.0
      dir = if x2 > x1, do: 1, else: -1
      do_line_x(x1, y1 + 0.0, x2, add, dir, [])
    end
  end

  defp do_line_y(x_real, y1, y2, _add, _dir, acc) when y1 == y2, do: Enum.reverse(acc)

  defp do_line_y(x_real, y1, y2, add, dir, acc) do
    point = {:set_pixel, trunc(x_real), y1}
    do_line_y(x_real + add, y1 + dir, y2, add, dir, [point | acc])
  end

  defp do_line_x(x1, y_real, x2, _add, _dir, acc) when x1 == x2, do: Enum.reverse(acc)

  defp do_line_x(x1, y_real, x2, add, dir, acc) do
    point = {:set_pixel, x1, trunc(y_real)}
    do_line_x(x1 + dir, y_real + add, x2, add, dir, [point | acc])
  end

  @doc """
  Write text at graphics position.
  Original: procedure GRWrite(ForStr: linetype; X,Y: integer) - lines 296-309
  Rendered characters from the ROM character table (CharTab8) into EGA memory
  with bit-shift rotation for sub-byte X alignment.
  """
  def gr_write(text, x, y) do
    {:draw_text, x, y, text}
  end

  @doc """
  Display a message at the bottom of screen (line 24).
  Original: procedure GRMessage(ForStr: linetype; WaitKey: boolean) - lines 366-393
  Centered the message, clearing previous message first.
  """
  def gr_message(text) do
    x = max(0, 40 - div(byte_size(text), 2))
    {:draw_text, x, 24, text}
  end

  @doc """
  Draw the vertical scale bar on the left edge.
  Original: procedure DrawScale - lines 465-478
  Drew a scale ruler from row 0 to 349, with markers at 10/50/100-pixel intervals.
  """
  def draw_scale do
    for i <- 0..349 do
      width =
        cond do
          rem(i, 100) == 0 -> 8
          rem(i, 50) == 0 -> 6
          rem(i, 10) == 0 -> 4
          true -> 2
        end

      {:fill_rect, 0, i, width, 1, 0xFF}
    end
  end

  @doc """
  Clear the circular radar display area.
  Original: procedure ClearScreen - lines 783-792
  Cleared within the circle boundary defined by Circle1 lookup table.
  """
  def clear_screen(circle1) do
    for i <- 0..175 do
      half_width = 1 + Bitwise.bsr(Enum.at(circle1, i), 3)
      x = 40 - half_width

      [
        {:clear_area, x, i, half_width * 2, 1},
        {:clear_area, x, 350 - i, half_width * 2, 1}
      ]
    end
    |> List.flatten()
  end

  @doc """
  Decompress and display a radar picture line.
  Original: procedure DispLine(var LinePtr) - lines 410-463
  The picture data was run-length encoded with 2-byte entries:
    bits 15-13: color (0=off, 1=red, 2=green, 3=yellow)
    bits 10-0: pixel count
  Terminated by $18 byte. Line number stored in first 2 bytes.
  """
  def disp_line(line_data) when is_binary(line_data) do
    <<line_num::little-16, rest::binary>> = line_data
    line_num = div(line_num, 54)
    {commands, _} = decode_line_segments(rest, line_num * 80, 0, [])
    {line_num, commands}
  end

  defp decode_line_segments(<<0x18, _rest::binary>>, _at_byte, _at_bit, acc) do
    {Enum.reverse(acc), :done}
  end

  defp decode_line_segments(<<hi, lo, rest::binary>>, at_byte, at_bit, acc) do
    size = Bitwise.bsl(Bitwise.band(hi, 0x07), 8) ||| lo

    color =
      case Bitwise.band(Bitwise.bsr(hi, 5), 0x03) do
        0 -> :off
        1 -> :red
        2 -> :green
        3 -> :yellow
      end

    # Generate pixel commands for this segment
    new_cmds =
      if color != :off do
        for pixel <- 0..(size - 1) do
          bit_pos = at_bit + pixel
          x = (at_byte + div(bit_pos, 8)) * 8 + rem(bit_pos, 8)
          y_offset = div(at_byte, 80)
          {:set_pixel, rem(x, 640), y_offset}
        end
      else
        []
      end

    new_at_bit = at_bit + size
    new_at_byte = at_byte + div(new_at_bit, 8)
    new_at_bit = rem(new_at_bit, 8)

    decode_line_segments(rest, new_at_byte, new_at_bit, new_cmds ++ acc)
  end

  defp decode_line_segments(<<>>, _at_byte, _at_bit, acc) do
    {Enum.reverse(acc), :truncated}
  end

  @doc """
  Initialize EGA mode (640x350 16-color).
  Original: procedure InitEGA - lines 480-508
  Set video mode $10 via BIOS INT 10h, loaded character tables,
  initialized palette registers, and drew initial parameter labels.
  Returns initial draw commands.
  """
  def init_ega(%TimeRec{} = time) do
    [
      {:clear_area, 0, 0, 640, 350},
      {:set_planes, MapSet.new([2])},
      {:draw_text, 0, 0, "TILT  : XXX"},
      {:draw_text, 65, 0, "TIME : " <> format_time(time)},
      {:draw_text, 0, 24, "RANGE : XXX"},
      {:draw_text, 65, 24, "GAIN  : XXX"},
      {:draw_text, 0, 22, "H = HELP"}
    ]
  end

  defp format_time(%TimeRec{hour: h, minute: m}) do
    h_str = if h < 13, do: "#{h}", else: "#{h - 12}"
    m_str = String.pad_leading("#{m}", 2, "0")
    suffix = if h > 12, do: "pm", else: "am"
    "#{String.pad_leading(h_str, 2)}:#{m_str}#{suffix}"
  end

  # ============================================================================
  # Renderer Behaviour
  # Original rendering went directly to EGA memory ($A000 segment).
  # This behaviour allows pluggable renderers.
  # ============================================================================

  @callback execute(draw_command()) :: :ok
  @callback execute_all([draw_command()]) :: :ok
  @callback present() :: :ok
end
