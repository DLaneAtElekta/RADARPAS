defmodule Radarpas do
  @moduledoc """
  RADARPAS - Ellason E300 Weather Radar Terminal, ver 2.1
  Elixir translation from the original Turbo Pascal source (January 14, 1988).

  Original: Program Radar_Terminal (RADAR.PAS, 1,894 lines)
  Copyright (C) 1987 D. G. Lane. All rights reserved.

  This is a complete PC-based radar control and display system that
  communicated with remote Ellason E300 radar systems via 2400 baud modems.
  It featured real-time EGA graphics (640x350, 16 colors) and supported
  station management, picture storage, map overlays, and live radar control.

  The Elixir translation preserves the original architecture and algorithms
  while adapting to modern idioms:
  - Global mutable state  → GenServer state
  - Hardware interrupts   → UART GenServer messages
  - Direct EGA memory     → Abstract draw commands
  - DOS file I/O          → Elixir File module
  - Inline x86 assembly   → Elixir binary pattern matching
  """
end

defmodule Radarpas.Application do
  @moduledoc """
  OTP Application for RADARPAS.
  Translates the original main program block (lines 1867-1886).

  Original main program:
    GetDir(0, OldDir);
    Initialize;
    [Display title screen]
    SelectStation;
    ModemLoop;
    DeInit;
    TextMode;
    ChDir(OldDir);
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Communication GenServer (replaces RS232 interrupt handler)
      {Radarpas.Communication, []},
      # Main radar application logic (replaces global state + main loops)
      {Radarpas.Radar, []}
    ]

    opts = [strategy: :one_for_one, name: Radarpas.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
