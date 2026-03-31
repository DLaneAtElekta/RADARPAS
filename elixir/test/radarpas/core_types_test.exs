defmodule Radarpas.CoreTypesTest do
  use ExUnit.Case, async: true

  alias Radarpas.CoreTypes
  alias Radarpas.CoreTypes.{TimeRec, PicRec}

  describe "tilt_val/1" do
    test "returns correct values from lookup table" do
      # Original: TiltVal: array[TiltType] of byte = (0,1,2,3,4,5,6,8,10,12,15,20)
      assert CoreTypes.tilt_val(0) == 0
      assert CoreTypes.tilt_val(5) == 5
      assert CoreTypes.tilt_val(7) == 8
      assert CoreTypes.tilt_val(11) == 20
    end
  end

  describe "range_val/1" do
    test "returns correct values from lookup table" do
      # Original: RangeVal: array[RangeType] of byte = (10,25,50,100,200)
      assert CoreTypes.range_val(0) == 10
      assert CoreTypes.range_val(1) == 25
      assert CoreTypes.range_val(2) == 50
      assert CoreTypes.range_val(3) == 100
      assert CoreTypes.range_val(4) == 200
    end
  end

  describe "validation" do
    test "valid_tilt? accepts 0..11" do
      assert CoreTypes.valid_tilt?(0)
      assert CoreTypes.valid_tilt?(11)
      refute CoreTypes.valid_tilt?(-1)
      refute CoreTypes.valid_tilt?(12)
    end

    test "valid_range? accepts 0..4" do
      assert CoreTypes.valid_range?(0)
      assert CoreTypes.valid_range?(4)
      refute CoreTypes.valid_range?(5)
    end

    test "valid_gain? accepts 1..17" do
      assert CoreTypes.valid_gain?(1)
      assert CoreTypes.valid_gain?(17)
      refute CoreTypes.valid_gain?(0)
      refute CoreTypes.valid_gain?(18)
    end
  end

  describe "command constants" do
    test "match original Pascal constants" do
      # Original: OnOff=#1; TiltUp=#2; RangeUp=#3; SendPic=#4; etc.
      assert CoreTypes.on_off() == 0x01
      assert CoreTypes.tilt_up() == 0x02
      assert CoreTypes.range_up() == 0x03
      assert CoreTypes.send_pic() == 0x04
      assert CoreTypes.tilt_down() == 0x05
      assert CoreTypes.range_down() == 0x06
      assert CoreTypes.send_graph() == 0x0A
      assert CoreTypes.gain_up() == 0x0D
      assert CoreTypes.gain_down() == 0x0E
      assert CoreTypes.check_graph() == 0x10
    end
  end

  describe "PicRec.generate_file_name/1" do
    test "generates correct filename from picture parameters" do
      # Original: SavePic (lines 1131-1139)
      # FileName[1]:=Chr(Time.Hour div 10+48);  etc.
      pic = %PicRec{
        time: %TimeRec{hour: 9, minute: 30},
        tilt: 2,
        range: 1,
        gain: 6
      }

      assert PicRec.generate_file_name(pic) == "0930CBF.PIC"
    end

    test "handles midnight" do
      pic = %PicRec{time: %TimeRec{hour: 0, minute: 0}, tilt: 0, range: 0, gain: 1}
      assert PicRec.generate_file_name(pic) == "0000AA@.PIC"
    end
  end

  describe "PicRec.parse_file_name/1" do
    test "parses valid filename" do
      # Original: LoadStation (lines 1241-1248)
      {:ok, pic} = PicRec.parse_file_name("0930CBF.PIC")
      assert pic.time.hour == 9
      assert pic.time.minute == 30
      assert pic.tilt == 2
      assert pic.range == 1
      assert pic.gain == 6
    end

    test "rejects invalid filename" do
      assert {:error, _} = PicRec.parse_file_name("X")
    end
  end
end
