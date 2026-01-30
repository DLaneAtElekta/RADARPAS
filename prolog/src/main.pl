%% ============================================================================
%% RADARPAS Prolog Translation - Main Control Logic
%% ============================================================================
%% Translation of the main control loops and command execution from RADAR.PAS.
%% Implements the state machines for Modem, Interactive, and RxPic modes.
%%
%% The original program has three main loops:
%%   ModemLoop    - Station selection, picture browsing, configuration
%%   InterLoop    - Real-time radar parameter control via F-keys
%%   RxPicLoop    - Picture reception with progress display
%%
%% In Prolog, these are modeled as state transformations driven by
%% keyboard/serial events.
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(main, [
    % Application state
    make_app_state/1,
    app_mode/2,
    app_catalog/2,
    app_station/2,

    % Event processing
    process_event/3,

    % Command execution
    exec_command/3,

    % Mode-specific event handlers
    modem_event/3,
    interactive_event/3,
    rx_pic_event/3,

    % Key mapping
    key_to_command/2,
    fkey_to_command/3,

    % Initialization
    initialize/1,
    deinitialize/2,

    % Configuration
    config_option/3,

    % Main entry point
    radar_terminal/0
]).

:- use_module(types).
:- use_module(protocol).
:- use_module(rs232).
:- use_module(graphics).
:- use_module(screen).
:- use_module(storage).
:- use_module(stations).

%% ============================================================================
%% Application State
%% ============================================================================
%% app_state(Mode, RS232, Graphics, Screen, Catalog, StationDir,
%%           CurrentStation, Config, PictureSaved)
%%
%% Bundles all subsystem states into a single application state

make_app_state(
    app_state(modem, RS232, Gfx, Screen, Catalog, StationDir,
              '', config(0, 0x3F8, 0, 0, ''), false)
) :-
    make_rs232_state(RS232),
    make_graphics_state(Gfx),
    make_screen_state(Screen),
    make_catalog(Catalog),
    make_station_dir(StationDir).

app_mode(app_state(Mode, _, _, _, _, _, _, _, _), Mode).
app_catalog(app_state(_, _, _, _, Cat, _, _, _, _), Cat).
app_station(app_state(_, _, _, _, _, _, Station, _, _), Station).

%% ============================================================================
%% Key Mapping
%% ============================================================================

%% key_to_command(+Key, -Command)
%% Map regular key codes to commands
%% Original: case UpCase(Key) of in ExecCom
key_to_command(0'G, toggle_graphics).
key_to_command(0'g, toggle_graphics).
key_to_command(0'R, toggle_range_marks).
key_to_command(0'r, toggle_range_marks).
key_to_command(0'H, toggle_help).
key_to_command(0'h, toggle_help).
key_to_command(0'1, toggle_map1).
key_to_command(0'2, toggle_map2).
key_to_command(0'+, next_pic).
key_to_command(0'-, prev_pic).
key_to_command(27,  escape).  % ESC

%% fkey_to_command(+Mode, +FKeyCode, -Command)
%% Map function key codes to mode-specific commands
%% Original: case Key of #59..#65 in InterLoop and ModemLoop

% Modem mode function keys
fkey_to_command(modem, 59, select_station).    % F1
fkey_to_command(modem, 60, call_station).      % F2
fkey_to_command(modem, 61, storage).           % F3

% Interactive mode function keys
fkey_to_command(interactive, 59, tilt_up).     % F1
fkey_to_command(interactive, 60, tilt_down).   % F2
fkey_to_command(interactive, 61, range_up).    % F3
fkey_to_command(interactive, 62, range_down).  % F4
fkey_to_command(interactive, 63, gain_up).     % F5
fkey_to_command(interactive, 64, gain_down).   % F6
fkey_to_command(interactive, 65, send_pic).    % F7

%% ============================================================================
%% Command Execution (ExecCom)
%% ============================================================================
%% Original: procedure ExecCom - processes regular key codes

%% exec_command(+Command, +StateIn, -StateOut)

% Toggle all graphics overlay visibility
exec_command(toggle_graphics,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, NewGfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    toggle_graphics(Gfx, NewGfx).

% Toggle range mark circles
exec_command(toggle_range_marks,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, Gfx, NewScr, Cat, SD, Sta, Cfg, PS)
) :-
    toggle_range_marks(Scr, NewScr).

% Toggle help display
exec_command(toggle_help,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, Gfx, NewScr, Cat, SD, Sta, Cfg, PS)
) :-
    toggle_help(Scr, NewScr).

% Toggle map overlay 1
exec_command(toggle_map1,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, Gfx, NewScr, Cat, SD, Sta, Cfg, PS)
) :-
    Sta \= '',
    toggle_gfx1(Scr, NewScr).

% Toggle map overlay 2
exec_command(toggle_map2,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, Gfx, NewScr, Cat, SD, Sta, Cfg, PS)
) :-
    Sta \= '',
    toggle_gfx2(Scr, NewScr).

% Next/previous picture
exec_command(next_pic,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, Gfx, Scr, NewCat, SD, Sta, Cfg, PS)
) :-
    next_pic(Cat, NewCat).

exec_command(prev_pic,
    app_state(Mode, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(Mode, RS, Gfx, Scr, NewCat, SD, Sta, Cfg, PS)
) :-
    prev_pic(Cat, NewCat).

% No-op for unmapped commands
exec_command(_, State, State).

%% ============================================================================
%% Modem Mode Event Handler
%% ============================================================================
%% Original: procedure ModemLoop

%% modem_event(+Event, +StateIn, -StateOut)

% F1: Select Station
modem_event(fkey(59), StateIn, StateOut) :-
    exec_command(select_station, StateIn, StateOut).

% F2: Call Station
modem_event(fkey(60),
    app_state(modem, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(NewMode, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    (   Sta \= ''
    ->  % Attempt connection
        station_phone(station(Sta, Phone), Phone),
        (   Phone \= ''
        ->  NewMode = interactive,
            NewRS = RS  % In reality, would initiate modem dial
        ;   NewMode = interactive,  % Direct connection if no phone
            NewRS = RS
        )
    ;   NewMode = modem,
        NewRS = RS
    ).

% F3: Storage menu
modem_event(fkey(61), State, State).
% Storage dialog would be shown here

% Regular key: delegate to exec_command
modem_event(key(K), StateIn, StateOut) :-
    key_to_command(K, Cmd),
    exec_command(Cmd, StateIn, StateOut).

% +/- keys: browse pictures
modem_event(key(0'+), StateIn, StateOut) :-
    exec_command(next_pic, StateIn, StateOut).
modem_event(key(0'-), StateIn, StateOut) :-
    exec_command(prev_pic, StateIn, StateOut).

% ESC: quit (after confirmation)
modem_event(key(27), State, State).
% Would trigger: Ask('QUIT PROGRAM')

% Default: no action
modem_event(_, State, State).

%% ============================================================================
%% Interactive Mode Event Handler
%% ============================================================================
%% Original: procedure InterLoop

%% interactive_event(+Event, +StateIn, -StateOut)

% F1: Tilt Up
interactive_event(fkey(59),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(interactive, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    send_command(tilt_up, [], RS, NewRS).

% F2: Tilt Down
interactive_event(fkey(60),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(interactive, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    send_command(tilt_down, [], RS, NewRS).

% F3: Range Up
interactive_event(fkey(61),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(interactive, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    send_command(range_up, [], RS, NewRS).

% F4: Range Down
interactive_event(fkey(62),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(interactive, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    send_command(range_down, [], RS, NewRS).

% F5: Gain Up
interactive_event(fkey(63),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(interactive, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    send_command(gain_up, [], RS, NewRS).

% F6: Gain Down
interactive_event(fkey(64),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(interactive, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    send_command(gain_down, [], RS, NewRS).

% F7: Request Picture
interactive_event(fkey(65),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, _),
    app_state(wait_pic, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, false)
) :-
    send_command(send_pic, [], RS, NewRS).

% ESC: Disconnect (after confirmation)
interactive_event(key(27),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(modem, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, PS)
) :-
    hang_up(RS, NewRS).

% Regular key: delegate to ExecCom
interactive_event(key(K), StateIn, StateOut) :-
    K \= 27,
    key_to_command(K, Cmd),
    exec_command(Cmd, StateIn, StateOut).

% Default: no action
interactive_event(_, State, State).

%% ============================================================================
%% RxPic Mode Event Handler
%% ============================================================================
%% Original: procedure RxPicLoop

%% rx_pic_event(+Event, +StateIn, -StateOut)

% Incoming picture data
rx_pic_event(serial_data(Data),
    app_state(rx_pic, RS, Gfx, Scr, Cat, SD, Sta, Cfg, _),
    app_state(rx_pic, NewRS, NewGfx, Scr, Cat, SD, Sta, Cfg, false)
) :-
    handle_interrupt(Data, RS, NewRS, Action),
    (   Action = pic_data(_)
    ->  NewGfx = Gfx  % Would decompress and display
    ;   NewGfx = Gfx
    ).

% Picture complete
rx_pic_event(pic_complete,
    app_state(rx_pic, RS, Gfx, Scr, Cat, SD, Sta, Cfg, _),
    app_state(modem, NewRS, Gfx, Scr, Cat, SD, Sta, Cfg, true)
) :-
    hang_up(RS, NewRS).

% ESC: Abort picture (after confirmation)
rx_pic_event(key(27),
    app_state(rx_pic, RS, Gfx, Scr, Cat, SD, Sta, Cfg, _),
    app_state(interactive, RS, Gfx, Scr, Cat, SD, Sta, Cfg, false)
).

% Regular keys still processed during reception
rx_pic_event(key(K), StateIn, StateOut) :-
    K \= 27,
    key_to_command(K, Cmd),
    exec_command(Cmd, StateIn, StateOut).

% Default: no action
rx_pic_event(_, State, State).

%% ============================================================================
%% General Event Processing
%% ============================================================================

%% process_event(+Event, +StateIn, -StateOut)
%% Route event to appropriate mode handler
process_event(Event, StateIn, StateOut) :-
    app_mode(StateIn, Mode),
    (   Mode = modem       -> modem_event(Event, StateIn, StateOut)
    ;   Mode = interactive -> interactive_event(Event, StateIn, StateOut)
    ;   Mode = rx_pic      -> rx_pic_event(Event, StateIn, StateOut)
    ;   StateOut = StateIn
    ).

%% ============================================================================
%% Initialization
%% ============================================================================

%% initialize(-AppState)
%% Initialize the complete application
%% Original: procedure Initialize
initialize(AppState) :-
    make_app_state(AppState).

%% deinitialize(+StateIn, -StateOut)
%% Clean up before exit
%% Original: procedure DeInit
deinitialize(
    app_state(_, RS, Gfx, Scr, Cat, SD, Sta, Cfg, PS),
    app_state(modem, NewRS, Gfx, Scr, Cat, SD, '', Cfg, PS)
) :-
    hang_up(RS, NewRS).

%% ============================================================================
%% Configuration
%% ============================================================================

%% config_option(+OptionName, +ConfigIn, -Value)
%% Access configuration options
%% Original: procedure Config
config_option(modem_type, config(MT, _, _, _, _), MT).
config_option(com_port,   config(_, CP, _, _, _), CP).
config_option(printer,    config(_, _, P, _, _), P).
config_option(clock_mode, config(_, _, _, CM, _), CM).
config_option(dir_path,   config(_, _, _, _, DP), DP).

%% ============================================================================
%% Main Entry Point
%% ============================================================================

%% radar_terminal/0
%% Start the RADAR terminal application
%% Original: main program block
radar_terminal :-
    format('~n', []),
    format('==========================================================~n', []),
    format('  ELLASON E300 RADAR TERMINAL, ver 2.1~n', []),
    format('            Revision 1/14/88~n', []),
    format('           Copyright (C) 1987~n', []),
    format('               D. G. Lane~n', []),
    format('           All rights reserved~n', []),
    format('==========================================================~n', []),
    format('  Prolog Translation~n', []),
    format('~n', []),

    initialize(InitState),
    format('System initialized.~n', []),
    format('Mode: modem~n', []),
    format('~n', []),
    format('Available commands:~n', []),
    format('  process_event(key(0\\'G), State, NewState)  - Toggle graphics~n', []),
    format('  process_event(key(0\\'R), State, NewState)  - Toggle range marks~n', []),
    format('  process_event(key(0\\'H), State, NewState)  - Toggle help~n', []),
    format('  process_event(fkey(59), State, NewState)   - F1 action~n', []),
    format('  process_event(fkey(60), State, NewState)   - F2 action~n', []),
    format('~n', []),
    format('Initial state: ~w~n', [InitState]).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
