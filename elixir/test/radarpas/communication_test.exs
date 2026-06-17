defmodule Radarpas.CommunicationTest do
  use ExUnit.Case, async: true

  alias Radarpas.Communication
  alias Radarpas.CoreTypes.{TimeRec, PicRec}

  describe "set_params/2" do
    test "parses valid Q-response from E300 radar" do
      # Original: procedure SetParams - lines 906-939
      # Construct a valid Q-response:
      # Byte 1: 'Q'
      # Byte 2: Gain (upper nibble = 8, so gain = 9) => 0x80
      # Byte 3: Tilt (12 - lower nibble; lower = 7, tilt = 5), RT flags => 0x97
      #         bit 7 = 1 (RT=1 check), bit 4 = 1 => RT = 1
      # Byte 4: Range (bits 3-5 = $30 => range 2) => 0x30
      # Byte 5: reserved => 0x00
      # Bytes 6-9: "1430" (14:30) => 0x31, 0x34, 0x33, 0x30
      # Byte 10: checksum

      b2 = 0x80
      b3 = 0x97
      b4 = 0x30
      b5 = 0x00
      b6 = ?1
      b7 = ?4
      b8 = ?3
      b9 = ?0
      checksum = Bitwise.band(b2 + b3 + b4 + b5 + b6 + b7 + b8 + b9, 0xFF)

      buf = <<?Q, b2, b3, b4, b5, b6, b7, b8, b9, checksum>>

      {response, pic, rt} = Communication.set_params(buf, %PicRec{})

      assert response == true
      assert pic.gain == 9
      assert pic.tilt == 5
      assert pic.range == 2
      assert pic.time.hour == 14
      assert pic.time.minute == 30
      assert rt == 1
    end

    test "rejects response with bad checksum" do
      buf = <<?Q, 0, 0, 0, 0, ?0, ?0, ?0, ?0, 0xFF>>
      {response, _pic, _rt} = Communication.set_params(buf, %PicRec{})
      assert response == false
    end

    test "rejects non-Q response" do
      buf = <<?X, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
      {response, _pic, _rt} = Communication.set_params(buf, %PicRec{})
      assert response == false
    end

    test "parses PRE gain (bit 5 of byte 3 set)" do
      # When bit 5 of byte 3 is set, gain = 17 (PRE/preset)
      b2 = 0x50
      b3 = 0xA5  # bit 5 set, lower nibble = 5 => tilt = 7
      b4 = 0x08  # range = 1
      b5 = 0x00
      b6 = ?0
      b7 = ?8
      b8 = ?1
      b9 = ?5
      checksum = Bitwise.band(b2 + b3 + b4 + b5 + b6 + b7 + b8 + b9, 0xFF)

      buf = <<?Q, b2, b3, b4, b5, b6, b7, b8, b9, checksum>>
      {response, pic, _rt} = Communication.set_params(buf, %PicRec{})

      assert response == true
      assert pic.gain == 17
    end

    test "parses all range values" do
      # Original: case (byte(Buf[4]) and $38) of
      #   $08: Range:=1; $30: Range:=2; $00: Range:=3; $20: Range:=4; $28: Range:=0
      range_codes = [{0x28, 0}, {0x08, 1}, {0x30, 2}, {0x00, 3}, {0x20, 4}]

      for {code, expected_range} <- range_codes do
        b2 = 0x10
        b3 = 0x9C  # tilt=0 (12-12=0), RT bits
        b4 = code
        b5 = 0x00
        b6 = ?1
        b7 = ?2
        b8 = ?0
        b9 = ?0
        checksum = Bitwise.band(b2 + b3 + b4 + b5 + b6 + b7 + b8 + b9, 0xFF)

        buf = <<?Q, b2, b3, b4, b5, b6, b7, b8, b9, checksum>>
        {true, pic, _rt} = Communication.set_params(buf, %PicRec{})
        assert pic.range == expected_range, "Expected range #{expected_range} for code #{code}"
      end
    end
  end
end
