defmodule RadarpasTest do
  use ExUnit.Case

  test "application module is defined" do
    assert Code.ensure_loaded?(Radarpas)
    assert Code.ensure_loaded?(Radarpas.Application)
  end

  test "all modules are defined" do
    modules = [
      Radarpas.CoreTypes,
      Radarpas.CoreTypes.TimeRec,
      Radarpas.CoreTypes.PicRec,
      Radarpas.Graphics,
      Radarpas.Screen,
      Radarpas.Communication,
      Radarpas.Pictures,
      Radarpas.Stations,
      Radarpas.ScreenDump,
      Radarpas.Radar,
      Radarpas.Radar.Config
    ]

    for mod <- modules do
      assert Code.ensure_loaded?(mod), "Module #{mod} should be defined"
    end
  end
end
