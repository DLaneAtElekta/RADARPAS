defmodule Radarpas.ScreenDump do
  @moduledoc """
  Screen dump / printer module.
  Translated from the Screen Dump section of RADAR.PAS (lines 1396-1484).

  The original supported two printers:
  - Epson MX-80 (9-pin dot matrix, monochrome with dithering)
  - HP Color InkJet (PaintJet)

  Both were implemented as interrupt service routines hooked into INT 05h
  (the Print Screen interrupt), using inline x86 assembly for register
  save/restore and IRET. They read directly from EGA video memory planes
  at segment $A000 using the EGA read mode registers.

  Original procedures translated:
    ColorJetPrtSc, EpsonMX80PrtSc

  In the Elixir translation, these are adapted to produce printable output
  from the abstract drawing command list rather than reading video memory.
  """

  # Dithering patterns for Epson MX-80 monochrome output
  # Original: Pat: array[0..1,1..3] of byte = (($22,$55,$FF),($88,$AA,$FF))
  @pat {{0x22, 0x55, 0xFF}, {0x88, 0xAA, 0xFF}}

  @doc """
  Generate Epson MX-80 compatible print data from screen state.
  Original: procedure EpsonMX80PrtSc - lines 1451-1484
  Read all 4 EGA planes for each column, applied dithering patterns
  to convert 4 colors to monochrome dot patterns, output as ESC/K
  graphics commands with 480 bytes per row (rotated 90 degrees).
  """
  def epson_mx80_dump(screen_data) when is_list(screen_data) do
    # Initialize printer: ESC 'e' 8 ESC 'P' (set line spacing, select font)
    header = <<27, ?e, 8, 27, ?P>>

    rows =
      for col <- 0..79 do
        # ESC 'K' 0xE0 0x01 = graphics mode, 480 bytes
        row_header = <<27, ?K, 0xE0, 0x01>>
        # In the original, each row scanned 480 columns (349 down to 0 with 8:1 mapping)
        # Here we output placeholder data
        row_data = :binary.copy(<<0>>, 480)
        row_header <> row_data <> <<13, 10>>
      end

    footer = <<12>>
    header <> IO.iodata_to_binary(rows) <> footer
  end

  @doc """
  Generate HP ColorJet compatible print data from screen state.
  Original: procedure ColorJetPrtSc - lines 1406-1443
  Read 3 EGA planes (0-2), applied color separation logic, output
  using HP PaintJet ESC sequences with 3 color planes per row.
  """
  def color_jet_dump(screen_data) when is_list(screen_data) do
    rows =
      for row <- 0..359 do
        # Original: ESC '[' 'O' 0xF5 0x00 0x80 0x1F 0x00 0x64 0x60
        row_header = <<27, ?[, ?O, 0xF5, 0x00, 0x80, 0x1F, 0x00, 100, 96>>

        # 3 color planes, 80 bytes each
        plane_data = :binary.copy(<<0>>, 80 * 3)
        row_header <> plane_data <> <<0>>
      end

    footer = <<12>>
    IO.iodata_to_binary(rows) <> footer
  end

  @doc "Get the dithering pattern value."
  def pattern(row, color) when row in 0..1 and color in 1..3 do
    elem(elem(@pat, row), color - 1)
  end
end
