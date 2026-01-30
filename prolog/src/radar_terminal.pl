%% ============================================================================
%% RADARPAS Prolog Translation - Entry Point
%% ============================================================================
%% Main entry point for the RADAR Terminal Prolog translation.
%% Loads all modules and provides the top-level predicates.
%%
%% Original: RADAR.PAS (Program Radar_Terminal)
%% Author: D. G. Lane, January 14, 1988
%% Translation: Prolog (SWI-Prolog compatible)
%%
%% Usage:
%%   $ swipl -l src/radar_terminal.pl
%%   ?- radar_terminal.
%%   ?- run_tests.
%%
%% ============================================================================

:- use_module(types).
:- use_module(protocol).
:- use_module(rs232).
:- use_module(graphics).
:- use_module(screen).
:- use_module(storage).
:- use_module(stations).
:- use_module(main).

%% ============================================================================
%% Top-Level Predicates
%% ============================================================================

%% start/0 - Alias for radar_terminal/0
start :- radar_terminal.

%% ============================================================================
%% Self-Test / Demonstration
%% ============================================================================

%% run_tests/0
%% Run basic verification tests on the translation
run_tests :-
    format('~n=== RADARPAS Prolog Translation Tests ===~n~n', []),

    % Test 1: Type validation
    format('Test 1: Type validation...~n', []),
    (   valid_tilt(0), valid_tilt(11), \+ valid_tilt(12),
        valid_range(0), valid_range(4), \+ valid_range(5),
        valid_gain(1), valid_gain(17), \+ valid_gain(0),
        valid_mode(modem), valid_mode(interactive),
        \+ valid_mode(invalid_mode)
    ->  format('  PASS: Type validation correct~n', [])
    ;   format('  FAIL: Type validation error~n', [])
    ),

    % Test 2: Lookup tables
    format('Test 2: Lookup tables...~n', []),
    (   tilt_value(0, 0), tilt_value(7, 8), tilt_value(11, 20),
        range_value(0, 10), range_value(2, 50), range_value(4, 200)
    ->  format('  PASS: Lookup tables correct~n', [])
    ;   format('  FAIL: Lookup table error~n', [])
    ),

    % Test 3: Command codes
    format('Test 3: Command codes...~n', []),
    (   command_code(tilt_up, 2), command_code(tilt_down, 5),
        command_code(range_up, 3), command_code(range_down, 6),
        command_code(gain_up, 13), command_code(gain_down, 14),
        command_code(send_pic, 4), command_code(check_graph, 16)
    ->  format('  PASS: Command codes correct~n', [])
    ;   format('  FAIL: Command code error~n', [])
    ),

    % Test 4: Command formatting
    format('Test 4: Command formatting...~n', []),
    (   format_command(tilt_up, [0x5A, 2]),
        format_command(range_down, [0x5A, 6])
    ->  format('  PASS: Command formatting correct~n', [])
    ;   format('  FAIL: Command formatting error~n', [])
    ),

    % Test 5: Protocol decoding
    format('Test 5: Protocol decoding...~n', []),
    (   decode_gain(0x50, 6),         % (0x50 >> 4) + 1 = 5 + 1 = 6
        decode_tilt(0x06, 6),         % 12 - 6 = 6
        decode_range_bits(0x08, 1),   % 25 km
        decode_range_bits(0x30, 2),   % 50 km
        decode_range_bits(0x00, 3),   % 100 km
        decode_rt_status(0x00, 2),    % Bit 7 clear -> RT=2
        decode_rt_status(0x90, 1),    % Bit 7 set, Bit 4 set -> RT=1
        decode_rt_status(0x80, 0)     % Bit 7 set, Bit 4 clear -> RT=0
    ->  format('  PASS: Protocol decoding correct~n', [])
    ;   format('  FAIL: Protocol decoding error~n', [])
    ),

    % Test 6: Time record
    format('Test 6: Time records...~n', []),
    (   make_time_rec(14, 30, T),
        time_hour(T, 14),
        time_minute(T, 30)
    ->  format('  PASS: Time records correct~n', [])
    ;   format('  FAIL: Time record error~n', [])
    ),

    % Test 7: Picture filename generation
    format('Test 7: Filename generation...~n', []),
    (   pic_filename_from_params(14, 30, 6, 2, 8, FN),
        atom_codes(FN, Codes),
        Codes = [0'1, 0'4, 0'3, 0'0, 0'G, 0'C, 0'H, 0'., 0'P, 0'I, 0'C]
    ->  format('  PASS: Filename generation correct (~w)~n', [FN])
    ;   format('  FAIL: Filename generation error~n', [])
    ),

    % Test 8: RS232 buffer operations
    format('Test 8: RS232 buffer operations...~n', []),
    (   make_rs232_state(S0),
        buffer_empty(S0),
        buffer_push(65, S0, S1),
        buffer_push(66, S1, S2),
        \+ buffer_empty(S2),
        buffer_pop(S2, 65, S3),
        buffer_pop(S3, 66, S4),
        buffer_empty(S4)
    ->  format('  PASS: Buffer operations correct~n', [])
    ;   format('  FAIL: Buffer operations error~n', [])
    ),

    % Test 9: Picture catalog
    format('Test 9: Picture catalog...~n', []),
    (   make_catalog(C0),
        catalog_max(C0, 0),
        make_time_rec(10, 30, T1),
        make_pic_rec('TEST.PIC', 0, 0, T1, 5, 2, 8, Pic1),
        insert_pic(Pic1, C0, C1),
        catalog_max(C1, 1)
    ->  format('  PASS: Picture catalog correct~n', [])
    ;   format('  FAIL: Picture catalog error~n', [])
    ),

    % Test 10: Application state
    format('Test 10: Application state...~n', []),
    (   make_app_state(AppState),
        app_mode(AppState, modem),
        process_event(key(0'G), AppState, NewState),
        app_mode(NewState, modem)  % Mode unchanged by 'G' key
    ->  format('  PASS: Application state correct~n', [])
    ;   format('  FAIL: Application state error~n', [])
    ),

    % Test 11: RLE decompression
    format('Test 11: RLE color decoding...~n', []),
    (   decode_color(0, none),
        decode_color(1, red),
        decode_color(2, green),
        decode_color(3, both)
    ->  format('  PASS: RLE color decoding correct~n', [])
    ;   format('  FAIL: RLE color decoding error~n', [])
    ),

    % Test 12: Modem responses
    format('Test 12: Modem response mapping...~n', []),
    (   modem_response_meaning(0'1, connected_2400),
        modem_response_meaning(0'3, no_carrier),
        modem_response_meaning(0'7, busy)
    ->  format('  PASS: Modem response mapping correct~n', [])
    ;   format('  FAIL: Modem response mapping error~n', [])
    ),

    format('~n=== All tests complete ===~n', []).

%% ============================================================================
%% Module Summary
%% ============================================================================

%% list_modules/0
%% Display available modules and their purposes
list_modules :-
    format('~nRADARPAS Prolog Translation - Module Summary~n', []),
    format('=============================================~n~n', []),
    format('  types.pl      - Core type definitions, constants, lookup tables~n', []),
    format('  protocol.pl   - RS-232 protocol parsing (Q response, commands)~n', []),
    format('  rs232.pl      - Serial communication (buffer, tx/rx, interrupt model)~n', []),
    format('  graphics.pl   - EGA graphics (planes, plotting, RLE decompression)~n', []),
    format('  screen.pl     - Display formatting (params, help, range circles, maps)~n', []),
    format('  storage.pl    - Picture file management (save, load, catalog)~n', []),
    format('  stations.pl   - Station directory (select, add, delete, phone)~n', []),
    format('  main.pl       - Control logic (modem/interactive/rxpic state machines)~n', []),
    format('~n', []),
    format('Entry point: radar_terminal.pl~n', []),
    format('  ?- start.          %% Launch terminal~n', []),
    format('  ?- run_tests.      %% Run self-tests~n', []),
    format('  ?- list_modules.   %% Show this summary~n', []).

%% ============================================================================
%% END OF ENTRY POINT
%% ============================================================================
