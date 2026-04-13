defmodule Radarpas.ScreenTest do
  use ExUnit.Case, async: true

  alias Radarpas.Screen
  alias Radarpas.CoreTypes
  alias Radarpas.CoreTypes.{TimeRec, PicRec}

  describe "write_rng_mks/0" do
    test "generates drawing commands for range marker circles" do
      commands = Screen.write_rng_mks()
      # Should generate many pixel commands (5 circles × symmetric points)
      assert length(commands) > 100
      # All commands should be set_pixel tuples
      assert Enum.all?(commands, fn cmd -> match?({:set_pixel, _, _}, cmd) end)
    end
  end

  describe "write_help/2" do
    test "generates help text for modem mode" do
      screen = %Screen{help_on: true}
      commands = Screen.write_help(screen, :modem)
      # Should include station selection and graphics help
      texts = for {:draw_text, _, _, text} <- commands, do: text
      assert Enum.any?(texts, &String.contains?(&1, "Select Station"))
      assert Enum.any?(texts, &String.contains?(&1, "All Graphics"))
    end

    test "generates help text for interactive mode" do
      screen = %Screen{help_on: true}
      commands = Screen.write_help(screen, :interactive)
      texts = for {:draw_text, _, _, text} <- commands, do: text
      assert Enum.any?(texts, &String.contains?(&1, "Disconnect"))
    end

    test "clears help when help_on is false" do
      screen = %Screen{help_on: false}
      commands = Screen.write_help(screen, :modem)
      # Should only have clearing commands (spaces)
      texts = for {:draw_text, _, _, text} <- commands, do: text
      assert Enum.all?(texts, &(String.trim(&1) == ""))
    end
  end

  describe "write_params/3" do
    test "formats picture parameters for display" do
      pic = %PicRec{
        tilt: 4,
        range: 2,
        gain: 9,
        time: %TimeRec{hour: 14, minute: 30}
      }

      commands = Screen.write_params(pic, 0, :modem)

      # Should have tilt, time, range, gain text commands
      assert length(commands) == 4

      texts = for {:draw_text, _, _, text} <- commands, do: text
      # TiltVal[4] = 4
      assert Enum.any?(texts, &String.contains?(&1, "4"))
      # RangeVal[2] = 50
      assert Enum.any?(texts, &String.contains?(&1, "50"))
    end

    test "shows RT status in interactive mode" do
      pic = %PicRec{tilt: 0, range: 0, gain: 1, time: %TimeRec{}}
      commands = Screen.write_params(pic, 1, :interactive)
      texts = for {:draw_text, _, _, text} <- commands, do: text
      assert Enum.any?(texts, &String.contains?(&1, "RT ON"))
    end

    test "shows XXX when no picture selected" do
      commands = Screen.write_params(nil, 0, :modem)
      texts = for {:draw_text, _, _, text} <- commands, do: text
      assert Enum.any?(texts, &(&1 == "XXX"))
    end
  end

  describe "lookup tables" do
    test "circle1 has 176 entries" do
      assert length(Screen.circle1()) == 176
    end

    test "a_sin has 361 entries (0..360 degrees)" do
      assert length(Screen.a_sin()) == 361
    end

    test "a_cos has 361 entries" do
      assert length(Screen.a_cos()) == 361
    end

    test "a_sin is centered at 128" do
      # At 0 and 180 degrees, sin should be ~0 (table value ~128)
      assert Enum.at(Screen.a_sin(), 0) == 128
      assert Enum.at(Screen.a_sin(), 180) == 128
      assert Enum.at(Screen.a_sin(), 360) == 128
    end

    test "a_sin peaks at 90 degrees" do
      # At 90 degrees, sin = 1.0, table value should be max (~153)
      peak = Enum.at(Screen.a_sin(), 90)
      assert peak >= 150
    end
  end
end
