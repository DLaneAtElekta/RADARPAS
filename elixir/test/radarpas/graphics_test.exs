defmodule Radarpas.GraphicsTest do
  use ExUnit.Case, async: true

  alias Radarpas.Graphics

  describe "line_points/4" do
    test "generates points for horizontal line" do
      # Original: GRLine with X-dominant path
      points = Graphics.line_points(0, 0, 5, 0)
      assert length(points) == 5

      # All points should have y=0
      for {:set_pixel, _x, y} <- points do
        assert y == 0
      end
    end

    test "generates points for vertical line" do
      # Original: GRLine with Y-dominant path
      points = Graphics.line_points(0, 0, 0, 5)
      assert length(points) == 5

      # All points should have x=0
      for {:set_pixel, x, _y} <- points do
        assert x == 0
      end
    end

    test "generates points for diagonal line" do
      points = Graphics.line_points(0, 0, 5, 5)
      assert length(points) == 5
    end
  end

  describe "plot/2" do
    test "returns set_pixel command" do
      assert {:set_pixel, 100, 200} = Graphics.plot(100, 200)
    end
  end

  describe "line/4" do
    test "returns draw_line command" do
      assert {:draw_line, 0, 0, 100, 100} = Graphics.line(0, 0, 100, 100)
    end
  end

  describe "gr_message/1" do
    test "creates centered text command" do
      {:draw_text, x, 24, "HELLO"} = Graphics.gr_message("HELLO")
      # Centered on 80-column display: 40 - 5/2 = 38
      assert x == 38
    end
  end

  describe "draw_scale/0" do
    test "generates 350 fill commands" do
      commands = Graphics.draw_scale()
      assert length(commands) == 350
    end

    test "wider markers at intervals" do
      commands = Graphics.draw_scale()
      # Row 0: rem(0,100)==0, width should be 8
      {:fill_rect, 0, 0, 8, 1, 0xFF} = Enum.at(commands, 0)
      # Row 50: rem(50,50)==0, width should be 6
      {:fill_rect, 0, 50, 6, 1, 0xFF} = Enum.at(commands, 50)
      # Row 10: rem(10,10)==0, width should be 4
      {:fill_rect, 0, 10, 4, 1, 0xFF} = Enum.at(commands, 10)
      # Row 1: none of the above, width should be 2
      {:fill_rect, 0, 1, 2, 1, 0xFF} = Enum.at(commands, 1)
    end
  end

  describe "state transformations" do
    test "select_plane updates current plane" do
      state = %Graphics{}
      new_state = Graphics.select_plane(state, [0, 1])
      assert MapSet.equal?(new_state.curr_plane, MapSet.new([0, 1]))
    end

    test "goto_xy updates cursor position" do
      state = %Graphics{}
      new_state = Graphics.goto_xy(state, 10, 20)
      assert new_state.curs_x == 10
      assert new_state.curs_y == 20
    end

    test "toggle_graphics flips graphics_on flag" do
      state = %Graphics{graphics_on: true}
      assert Graphics.toggle_graphics(state).graphics_on == false
      assert Graphics.toggle_graphics(Graphics.toggle_graphics(state)).graphics_on == true
    end

    test "window sets position and size limits" do
      state = %Graphics{}
      new_state = Graphics.window(state, 27, 1, 25, 21)
      assert new_state.x_pos == 27
      assert new_state.y_pos == 1
      assert new_state.x_max == 25
      assert new_state.y_max == 21
      assert new_state.curs_x == 0
      assert new_state.curs_y == 0
    end
  end
end
