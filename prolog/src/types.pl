%% ============================================================================
%% RADARPAS Prolog Translation - Core Types and Constants
%% ============================================================================
%% Translation of Pascal type definitions and constants from the original
%% 1988 RADAR.PAS (Ellason E300 Radar Terminal, Version 2.1)
%%
%% Original: D. G. Lane, January 14, 1988
%% Translation: Prolog (SWI-Prolog compatible)
%% ============================================================================

:- module(types, [
    % Type validation predicates
    valid_tilt/1,
    valid_range/1,
    valid_gain/1,
    valid_mode/1,
    valid_hour/1,
    valid_minute/1,

    % Lookup table predicates
    tilt_value/2,
    range_value/2,

    % Command code predicates
    command_code/2,

    % Record constructors / accessors
    make_time_rec/3,
    time_hour/2,
    time_minute/2,

    make_pic_rec/8,
    pic_filename/2,
    pic_file_date/2,
    pic_file_time/2,
    pic_time/2,
    pic_tilt/2,
    pic_range/2,
    pic_gain/2,

    % Constants
    com_port_default/1,
    modem_type_default/1,
    printer_default/1,
    clock_mode_default/1,

    % Color palette
    ega_color/2
]).

%% ============================================================================
%% Type Definitions (as validation predicates)
%% ============================================================================

%% TiltType = 0..11
%% 12 antenna tilt angle indices
valid_tilt(T) :- integer(T), T >= 0, T =< 11.

%% RangeType = 0..4
%% 5 range settings
valid_range(R) :- integer(R), R >= 0, R =< 4.

%% GainType = 1..17
%% Receiver gain 1-16, 17 = PRE-amplifier mode
valid_gain(G) :- integer(G), G >= 1, G =< 17.

%% ModeType = (Modem, Interactive, WaitPic, RxPic, RxGraph)
%% Operating modes as atoms
valid_mode(modem).
valid_mode(interactive).
valid_mode(wait_pic).
valid_mode(rx_pic).
valid_mode(rx_graph).

%% TimeRec validation
valid_hour(H)   :- integer(H), H >= 0, H =< 23.
valid_minute(M) :- integer(M), M >= 0, M =< 59.

%% ============================================================================
%% Lookup Tables
%% ============================================================================

%% TiltVal: array[TiltType] of byte = (0,1,2,3,4,5,6,8,10,12,15,20)
%% Maps tilt index to tilt angle in degrees
tilt_value(0, 0).
tilt_value(1, 1).
tilt_value(2, 2).
tilt_value(3, 3).
tilt_value(4, 4).
tilt_value(5, 5).
tilt_value(6, 6).
tilt_value(7, 8).
tilt_value(8, 10).
tilt_value(9, 12).
tilt_value(10, 15).
tilt_value(11, 20).

%% RangeVal: array[RangeType] of byte = (10,25,50,100,200)
%% Maps range index to range in kilometers
range_value(0, 10).
range_value(1, 25).
range_value(2, 50).
range_value(3, 100).
range_value(4, 200).

%% ============================================================================
%% Command Codes
%% ============================================================================
%% Constants for RADAR control commands sent via RS-232
%% Format: command_code(CommandName, ByteValue)

command_code(on_off,     1).    % OnOff = #1
command_code(tilt_up,    2).    % TiltUp = #2
command_code(range_up,   3).    % RangeUp = #3
command_code(send_pic,   4).    % SendPic = #4
command_code(tilt_down,  5).    % TiltDown = #5
command_code(range_down, 6).    % RangeDown = #6
command_code(send_graph, 10).   % SendGraph = #10
command_code(gain_up,    13).   % GainUp = #13
command_code(gain_down,  14).   % GainDown = #14
command_code(check_graph, 16).  % CheckGraph = #16

%% ============================================================================
%% Record Constructors and Accessors
%% ============================================================================

%% TimeRec = record Year, Month, Day, Hour, Minute end
%% Simplified to just Hour and Minute for the core protocol
make_time_rec(Hour, Minute, time_rec(Hour, Minute)) :-
    valid_hour(Hour),
    valid_minute(Minute).

time_hour(time_rec(H, _), H).
time_minute(time_rec(_, M), M).

%% PicRec = record FileName, FileDate, FileTime, Time, Tilt, Range, Gain end
%% Picture metadata record
make_pic_rec(FileName, FileDate, FileTime, Time, Tilt, Range, Gain,
             pic_rec(FileName, FileDate, FileTime, Time, Tilt, Range, Gain)) :-
    valid_tilt(Tilt),
    valid_range(Range),
    valid_gain(Gain).

pic_filename(pic_rec(F, _, _, _, _, _, _), F).
pic_file_date(pic_rec(_, D, _, _, _, _, _), D).
pic_file_time(pic_rec(_, _, T, _, _, _, _), T).
pic_time(pic_rec(_, _, _, T, _, _, _), T).
pic_tilt(pic_rec(_, _, _, _, T, _, _), T).
pic_range(pic_rec(_, _, _, _, _, R, _), R).
pic_gain(pic_rec(_, _, _, _, _, _, G), G).

%% ============================================================================
%% Hardware Constants
%% ============================================================================

%% Default COM port base address (COM1 = 0x3F8, COM2 = 0x2F8)
com_port_default(0x3F8).

%% Default modem type (0 = Hayes, 1 = Racal-Vadic)
modem_type_default(0).

%% Default printer (0 = Epson MX80, 1 = HP ColorJet)
printer_default(0).

%% Default clock mode (0 = 12-hour, 1 = 24-hour)
clock_mode_default(0).

%% ============================================================================
%% EGA Color Palette
%% ============================================================================
%% Colors: array[0..15] of byte
%% EGA palette register values

ega_color(0,  0x00).
ega_color(1,  36).
ega_color(2,  50).
ega_color(3,  54).
ega_color(4,  0x3F).
ega_color(5,  0x3F).
ega_color(6,  0x3F).
ega_color(7,  0x3F).
ega_color(8,  0x09).
ega_color(9,  0x09).
ega_color(10, 0x09).
ega_color(11, 0x09).
ega_color(12, 0x09).
ega_color(13, 0x09).
ega_color(14, 0x09).
ega_color(15, 0x09).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
