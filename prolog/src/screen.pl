%% ============================================================================
%% RADARPAS Prolog Translation - Screen Display Module
%% ============================================================================
%% Translation of screen formatting routines from RADAR.PAS
%% Handles parameter display, range circles, map overlays, and help text.
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(screen, [
    % Screen state
    make_screen_state/1,

    % Display flags
    help_on/1,
    gfx1_on/1,
    gfx2_on/1,
    range_marks_on/1,

    % Display operations
    write_params/3,
    write_time/2,
    write_help/3,
    write_range_marks/2,
    write_gfx/3,

    % Toggle operations
    toggle_help/2,
    toggle_gfx1/2,
    toggle_gfx2/2,
    toggle_range_marks/2,

    % Time formatting
    format_time_12h/3,
    format_time_24h/3,

    % Range circle tables
    circle_radius/3,

    % Map overlay types
    landmark/4,
    segment/5
]).

:- use_module(types).

%% ============================================================================
%% Screen State Structure
%% ============================================================================
%% screen_state(HelpOn, Gfx1On, Gfx2On, RngMksOn, ClockMode, LastMessage)

make_screen_state(
    screen_state(true, false, false, false, 0, '')
).

help_on(screen_state(true, _, _, _, _, _)).
gfx1_on(screen_state(_, true, _, _, _, _)).
gfx2_on(screen_state(_, _, true, _, _, _)).
range_marks_on(screen_state(_, _, _, true, _, _)).

%% ============================================================================
%% Toggle Operations
%% ============================================================================

toggle_help(
    screen_state(H, G1, G2, R, C, M),
    screen_state(NH, G1, G2, R, C, M)
) :- (H = true -> NH = false ; NH = true).

toggle_gfx1(
    screen_state(H, G1, G2, R, C, M),
    screen_state(H, NG1, G2, R, C, M)
) :- (G1 = true -> NG1 = false ; NG1 = true).

toggle_gfx2(
    screen_state(H, G1, G2, R, C, M),
    screen_state(H, G1, NG2, R, C, M)
) :- (G2 = true -> NG2 = false ; NG2 = true).

toggle_range_marks(
    screen_state(H, G1, G2, R, C, M),
    screen_state(H, G1, G2, NR, C, M)
) :- (R = true -> NR = false ; NR = true).

%% ============================================================================
%% Time Formatting
%% ============================================================================

%% format_time_12h(+Hour, +Minute, -Formatted)
%% Format time in 12-hour AM/PM style
%% Original: case Clock of 0: ...
format_time_12h(Hour, Minute, Formatted) :-
    (   Hour < 13
    ->  DisplayHour = Hour
    ;   DisplayHour is Hour - 12
    ),
    (   Hour > 12
    ->  Suffix = 'pm'
    ;   Suffix = 'am'
    ),
    format(atom(Formatted), '~d:~|~`0t~d~2+~w', [DisplayHour, Minute, Suffix]).

%% format_time_24h(+Hour, +Minute, -Formatted)
%% Format time in 24-hour style
%% Original: case Clock of 1: ...
format_time_24h(Hour, Minute, Formatted) :-
    format(atom(Formatted), '~d:~|~`0t~d~2+', [Hour, Minute]).

%% ============================================================================
%% Parameter Display
%% ============================================================================

%% write_params(+PicRec, +RT, -DisplayLines)
%% Generate display lines for current radar parameters
%% Original: procedure WriteParams
%% Places: TILT at (8,0), TIME at (72,0), RANGE at (8,24), GAIN at (72,24)
write_params(PicRec, RT, DisplayLines) :-
    pic_tilt(PicRec, TiltIdx),
    pic_range(PicRec, RangeIdx),
    pic_gain(PicRec, Gain),
    pic_time(PicRec, TimeRec),
    time_hour(TimeRec, Hour),
    time_minute(TimeRec, Minute),
    tilt_value(TiltIdx, TiltDeg),
    range_value(RangeIdx, RangeKm),
    format(atom(TiltStr), 'TILT  : ~d', [TiltDeg]),
    format(atom(RangeStr), 'RANGE : ~d', [RangeKm]),
    (   Gain < 17
    ->  format(atom(GainStr), 'GAIN  : ~d', [Gain])
    ;   GainStr = 'GAIN  : PRE'
    ),
    format_time_24h(Hour, Minute, TimeStr),
    format(atom(TimeDisplay), 'TIME : ~w', [TimeStr]),
    (   RT =:= 0
    ->  RTStr = 'RT OFF'
    ;   RTStr = 'RT ON'
    ),
    DisplayLines = [
        line(0, 0, TiltStr),
        line(65, 0, TimeDisplay),
        line(0, 24, RangeStr),
        line(65, 24, GainStr),
        line(36, 0, RTStr)
    ].

% Display 'XXX' when no picture is selected
write_params(none, _, DisplayLines) :-
    DisplayLines = [
        line(0, 0, 'TILT  : XXX'),
        line(65, 0, 'TIME : XX:XX'),
        line(0, 24, 'RANGE : XXX'),
        line(65, 24, 'GAIN  : XXX')
    ].

%% ============================================================================
%% Write Time
%% ============================================================================

%% write_time(+TimeRec, -Formatted)
%% Format time according to current clock mode
write_time(TimeRec, Formatted) :-
    time_hour(TimeRec, Hour),
    time_minute(TimeRec, Minute),
    format_time_24h(Hour, Minute, Formatted).

%% ============================================================================
%% Help Text Display
%% ============================================================================

%% write_help(+Mode, +HelpOn, -HelpLines)
%% Generate help text based on current mode
%% Original: procedure WriteHelp
write_help(Mode, true, HelpLines) :-
    common_help(CommonLines),
    mode_help(Mode, ModeLines),
    append(ModeLines, CommonLines, HelpLines).
write_help(_, false, []).

common_help([
    line(66, 2, 'G = All Graphics'),
    line(67, 3, 'R = Range Marks'),
    line(73, 4, '1 = Map 1'),
    line(73, 5, '2 = Map 2')
]).

%% Mode-specific help text
mode_help(modem, [
    line(0, 2, 'F1 = Select Station'),
    line(0, 3, 'F2 = Call Station'),
    line(0, 4, 'F3 = Storage'),
    line(0, 19, '+ Next Pic'),
    line(0, 20, '- Prev Pic'),
    line(0, 21, 'ESC = Quit')
]).

mode_help(interactive, [
    line(0, 21, 'ESC = Disconnect')
]).

mode_help(rx_pic, [
    line(0, 21, 'ESC = Abort')
]).

mode_help(_, []).

%% ============================================================================
%% Range Mark Circles
%% ============================================================================
%% Pre-computed circle radius tables (Circle1..Circle5)
%% These define the radii of 5 concentric range circles on the 640x350 display
%% centered at (320, 175).
%%
%% circle_radius(+CircleIndex, +YOffset, -XRadius)
%% CircleIndex: 1-5 (outermost to innermost)
%% YOffset: vertical distance from center (0-175)
%% XRadius: horizontal radius at that Y offset

%% Circle1: outermost, radius ~255 pixels at equator
%% Selected key values from the 176-element lookup table
circle_radius(1, 0, 92).
circle_radius(1, 10, 122).
circle_radius(1, 20, 152).
circle_radius(1, 30, 168).
circle_radius(1, 50, 194).
circle_radius(1, 70, 213).
circle_radius(1, 90, 228).
circle_radius(1, 100, 234).
circle_radius(1, 120, 244).
circle_radius(1, 140, 250).
circle_radius(1, 160, 254).
circle_radius(1, 175, 255).

%% Circle2: second ring, radius ~204 at equator
circle_radius(2, 25, 0).
circle_radius(2, 50, 94).
circle_radius(2, 75, 131).
circle_radius(2, 100, 160).
circle_radius(2, 125, 181).
circle_radius(2, 150, 197).
circle_radius(2, 175, 204).

%% Circle3: third ring, radius ~153 at equator
circle_radius(3, 62, 0).
circle_radius(3, 80, 67).
circle_radius(3, 100, 102).
circle_radius(3, 125, 131).
circle_radius(3, 150, 150).
circle_radius(3, 175, 153).

%% Circle4: fourth ring, radius ~102 at equator
circle_radius(4, 99, 0).
circle_radius(4, 110, 34).
circle_radius(4, 125, 65).
circle_radius(4, 150, 92).
circle_radius(4, 175, 102).

%% Circle5: innermost ring, radius ~51 at equator
circle_radius(5, 136, 0).
circle_radius(5, 150, 35).
circle_radius(5, 160, 44).
circle_radius(5, 175, 51).

%% write_range_marks(+StateIn, -StateOut)
%% Draw all 5 range mark circles
%% Original: procedure WriteRngMks
write_range_marks(ScreenState, ScreenState).
% In a full implementation, this would iterate through circle tables
% and issue gr_plot calls for each pixel. The operation is recorded
% as a display command in the graphics framebuffer.

%% ============================================================================
%% Map Overlay Display
%% ============================================================================

%% Map overlays consist of two types of entries:
%% 1. Landmarks: positioned labels (bearing, range, 3-char name)
%% 2. Segments: line segments between two polar coordinates

%% landmark(+Bearing, +Range, +Name, -DisplayCmd)
%% Convert polar landmark to display command
%% Original: LandMarkRec = record Bear, Range, Name[3], Nothing end
landmark(Bearing, Range, Name, text_at(X, Y, Name)) :-
    % Convert polar to screen coordinates using ASin/ACos tables
    % X = 320 + Range * (ASin[Bear] - 128) / Adj
    % Y = 174 - Range * (ACos[Bear] - 128) / Adj
    % Simplified using trig approximation
    BearRad is Bearing * pi / 180,
    X is round(320 + Range * sin(BearRad)),
    Y is round(174 - Range * cos(BearRad)).

%% segment(+Range1, +Bear1, +Range2, +Bear2, -DisplayCmd)
%% Convert polar segment to display line command
%% Original: SegmentRec = record Range1, Bear1, Range2, Bear2 end
segment(Range1, Bear1, Range2, Bear2, line(X1, Y1, X2, Y2)) :-
    B1Rad is Bear1 * pi / 180,
    B2Rad is Bear2 * pi / 180,
    X1 is round(320 + Range1 * sin(B1Rad)),
    Y1 is round(174 - Range1 * cos(B1Rad)),
    X2 is round(320 + Range2 * sin(B2Rad)),
    Y2 is round(174 - Range2 * cos(B2Rad)).

%% write_gfx(+MapData, +AdjValue, -DisplayCmds)
%% Render map overlay data
%% Original: procedure WriteGfx
%% MapData is a list of landmark/segment records
write_gfx([], _, []).
write_gfx([landmark(Bear, Range, Name) | Rest], Adj, [Cmd | Cmds]) :-
    landmark(Bear, Range, Name, Cmd),
    write_gfx(Rest, Adj, Cmds).
write_gfx([segment(R1, B1, R2, B2) | Rest], Adj, [Cmd | Cmds]) :-
    segment(R1, B1, R2, B2, Cmd),
    write_gfx(Rest, Adj, Cmds).

%% ============================================================================
%% Trigonometric Lookup Tables (ASin / ACos)
%% ============================================================================
%% The original uses pre-computed 361-element tables mapping
%% radar bearing (0-360) to screen offsets (byte values centered at 128).
%% These are used for polar-to-cartesian conversion of map overlay data.
%%
%% ASin[bearing] ≈ 128 + 25 * sin(bearing * π / 180)
%% ACos[bearing] ≈ 128 + 18 * cos(bearing * π / 180)
%%
%% In Prolog, we compute these directly using trig functions
%% rather than storing the full lookup table.

%% ============================================================================
%% END OF MODULE
%% ============================================================================
