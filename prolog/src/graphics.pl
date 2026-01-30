%% ============================================================================
%% RADARPAS Prolog Translation - Graphics Module
%% ============================================================================
%% Translation of EGA graphics routines from RADAR.PAS
%% Models the graphics operations as declarative transformations on a
%% framebuffer state, since Prolog cannot do direct hardware I/O.
%%
%% The original code directly manipulates EGA video memory at segment A000h
%% using plane selection, bit masking, and function selection registers.
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(graphics, [
    % Graphics state
    make_graphics_state/1,
    graphics_plane/2,
    graphics_func/2,
    graphics_cursor/3,
    graphics_char_size/2,
    graphics_window/5,

    % Plane operations
    select_plane/3,
    show_plane/3,

    % Function selection
    select_func/3,

    % Mask operations
    set_mask/3,

    % Cursor operations
    goto_xy/4,

    % Plotting primitives
    gr_plot/4,
    gr_line/6,

    % Text rendering
    gr_write_str/5,

    % Screen operations
    clear_screen/2,
    draw_scale/2,
    init_ega/2,

    % Window management
    open_window/6,
    un_window/2,

    % Message display
    gr_message/4,

    % Display line (RLE decompression)
    disp_line/4,

    % Toggle graphics
    toggle_graphics/2,

    % Graphics function types
    valid_func/1
]).

:- use_module(types).

%% ============================================================================
%% Graphics Function Types
%% ============================================================================
%% FuncType = (Rot1..Rot7, _Clr, _And, _Or, _Xor)
%% EGA ALU function selection

valid_func(rot1).
valid_func(rot2).
valid_func(rot3).
valid_func(rot4).
valid_func(rot5).
valid_func(rot6).
valid_func(rot7).
valid_func(clr).
valid_func('and').
valid_func('or').
valid_func('xor').

%% ============================================================================
%% Graphics State Structure
%% ============================================================================
%% gfx_state(Plane, Func, Mask, CursorX, CursorY,
%%           XPos, YPos, XMax, YMax, CharSize,
%%           GraphicsOn, Framebuffer)
%%
%% Plane:      Current selected EGA planes (list of 0..3)
%% Func:       Current ALU function (clr/and/or/xor/rotN)
%% Mask:       Current bit mask (0x00..0xFF)
%% CursorX/Y:  Text cursor position
%% XPos/YPos:  Window origin offset
%% XMax/YMax:  Window extent
%% CharSize:   Character height (8 or 14)
%% GraphicsOn: Whether graphics planes are visible
%% Framebuffer: Abstract representation of video memory

make_graphics_state(
    gfx_state([2], clr, 0xFF, 0, 0,
              0, 0, 79, 24, 14,
              true, [])
).

graphics_plane(gfx_state(P, _, _, _, _, _, _, _, _, _, _, _), P).
graphics_func(gfx_state(_, F, _, _, _, _, _, _, _, _, _, _), F).
graphics_cursor(gfx_state(_, _, _, X, Y, _, _, _, _, _, _, _), X, Y).
graphics_char_size(gfx_state(_, _, _, _, _, _, _, _, _, CS, _, _), CS).
graphics_window(gfx_state(_, _, _, _, _, XP, YP, XM, YM, _, _, _), XP, YP, XM, YM).

%% ============================================================================
%% Plane Operations
%% ============================================================================

%% select_plane(+Planes, +StateIn, -StateOut)
%% Select EGA planes for write operations
%% Original: port[$3C4]:=$02; port[$3C5]:=Data
select_plane(Planes,
    gfx_state(_, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    gfx_state(Planes, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB)
).

%% show_plane(+Planes, +StateIn, -StateOut)
%% Select EGA planes for display (attribute controller)
%% Original: port[$3C0]:=$12; port[$3C0]:=Data; port[$3C0]:=$20
show_plane(Planes,
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, _, FB),
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB)
) :-
    (   Planes = [0, 1, 2, 3] -> GO = true
    ;   Planes = [0, 1]       -> GO = false
    ;   GO = true  % default: show all
    ).

%% ============================================================================
%% Function Selection
%% ============================================================================

%% select_func(+Func, +StateIn, -StateOut)
%% Select EGA ALU function for bitwise operations
%% Original: port[$3CE]:=$03; port[$3CF]:=encoded_func
select_func(Func,
    gfx_state(P, _, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB)
) :-
    valid_func(Func).

%% ============================================================================
%% Mask Operations
%% ============================================================================

%% set_mask(+MaskValue, +StateIn, -StateOut)
%% Set bit mask register for pixel operations
%% Original: port[$3CE]:=$08; port[$3CF]:=ToMask
set_mask(MaskVal,
    gfx_state(P, Func, _, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    gfx_state(P, Func, MaskVal, CX, CY, XP, YP, XM, YM, CS, GO, FB)
).

%% ============================================================================
%% Cursor Operations
%% ============================================================================

%% goto_xy(+X, +Y, +StateIn, -StateOut)
%% Position text cursor
goto_xy(X, Y,
    gfx_state(P, Func, Mask, _, _, XP, YP, XM, YM, CS, GO, FB),
    gfx_state(P, Func, Mask, X, Y, XP, YP, XM, YM, CS, GO, FB)
).

%% ============================================================================
%% Plotting Primitives
%% ============================================================================

%% gr_plot(+X, +Y, +StateIn, -StateOut)
%% Plot single pixel at (X, Y)
%% Original: AtByte:=Y*80+(X shr 3); AtBit:=$80 shr (X and $07)
gr_plot(X, Y,
    gfx_state(P, Func, _, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    gfx_state(P, Func, 0xFF, CX, CY, XP, YP, XM, YM, CS, GO, NewFB)
) :-
    % Calculate byte offset and bit position
    AtByte is Y * 80 + (X >> 3),
    AtBit is 0x80 >> (X /\ 0x07),
    % Add pixel to framebuffer as operation record
    append(FB, [plot(AtByte, AtBit, P, Func)], NewFB).

%% gr_line(+X1, +Y1, +X2, +Y2, +StateIn, -StateOut)
%% Draw line from (X1,Y1) to (X2,Y2) using Bresenham-style algorithm
%% Original: incremental DDA line drawing
gr_line(X1, Y1, X2, Y2, StateIn, StateOut) :-
    % Record line drawing operation
    StateIn = gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    append(FB, [line(X1, Y1, X2, Y2, P, Func)], NewFB),
    StateOut = gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, NewFB).

%% ============================================================================
%% Text Rendering
%% ============================================================================

%% gr_write_str(+String, +X, +Y, +StateIn, -StateOut)
%% Write string at pixel coordinates using 8-pixel-wide character table
%% Original: procedure GRWrite with bit-shift blitting
gr_write_str(String, X, Y, StateIn, StateOut) :-
    StateIn = gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    append(FB, [text(String, X, Y, P, Func)], NewFB),
    StateOut = gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, NewFB).

%% ============================================================================
%% Screen Operations
%% ============================================================================

%% clear_screen(+StateIn, -StateOut)
%% Clear radar display area (circular region)
%% Original: uses Circle1 table to determine extent at each scanline
clear_screen(
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, _),
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, [clear])
).

%% draw_scale(+StateIn, -StateOut)
%% Draw range scale along left edge
%% Original: vertical lines with tick marks at 10, 50, 100 pixel intervals
draw_scale(StateIn, StateOut) :-
    StateIn = gfx_state(P, _, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    append(FB, [scale], NewFB),
    StateOut = gfx_state(P, clr, Mask, CX, CY, XP, YP, XM, YM, CS, GO, NewFB).

%% init_ega(+StateIn, -StateOut)
%% Initialize EGA 640x350 16-color mode
%% Original: BIOS INT 10h, AH=00, AL=10h
init_ega(_, State) :-
    make_graphics_state(State).

%% ============================================================================
%% Window Management
%% ============================================================================

%% open_window(+X, +Y, +XSize, +YSize, +StateIn, -StateOut)
%% Open a text window at character position (X,Y) with given size
%% Original: procedure Window - fills area with blue background
open_window(X, Y, XSize, YSize,
    gfx_state(P, Func, Mask, _, _, _, _, _, _, CS, GO, FB),
    gfx_state(P, Func, Mask, 0, 0, X, Y, XSize, YSize, CS, GO, NewFB)
) :-
    append(FB, [window(X, Y, XSize, YSize)], NewFB).

%% un_window(+StateIn, -StateOut)
%% Close window and restore full-screen display
%% Original: procedure UnWindow - clears and redraws overlays
un_window(
    gfx_state(P, Func, Mask, _, _, _, _, _, _, CS, GO, FB),
    gfx_state(P, Func, Mask, 0, 0, 0, 0, 79, 24, CS, GO, NewFB)
) :-
    append(FB, [un_window], NewFB).

%% ============================================================================
%% Message Display
%% ============================================================================

%% gr_message(+Text, +WaitForKey, +StateIn, -StateOut)
%% Display centered message at bottom of screen
%% Original: procedure GRMessage - opens temporary window at row 24
gr_message(Text, WaitForKey, StateIn, StateOut) :-
    StateIn = gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    append(FB, [message(Text, WaitForKey)], NewFB),
    StateOut = gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, GO, NewFB).

%% ============================================================================
%% Run-Length Decompression (DispLine)
%% ============================================================================

%% disp_line(+CompressedData, +StateIn, -StateOut, -LineNum)
%% Decompress and display one radar scan line
%% Original: procedure DispLine
%%
%% Compressed format: pairs of (control, size) bytes
%%   Control byte bits 5-6: color (0=none, 1=red, 2=green, 3=both)
%%   Control byte bits 0-2 + size byte: run length (11-bit)
%%   Terminator: 0x18 (Cancel character)
%%
%% In Prolog, we decode the RLE data into a list of run segments

disp_line(CompressedData, StateIn, StateOut, LineNum) :-
    % First two bytes are the line number (div 54)
    CompressedData = [LoByte, HiByte | RunData],
    RawLine is LoByte + (HiByte << 8),
    LineNum is RawLine // 54,

    % Decode runs
    decode_runs(RunData, Runs),

    % Record display operation
    StateIn = gfx_state(P, _, Mask, CX, CY, XP, YP, XM, YM, CS, GO, FB),
    append(FB, [radar_line(LineNum, Runs)], NewFB),
    StateOut = gfx_state(P, clr, Mask, CX, CY, XP, YP, XM, YM, CS, GO, NewFB).

%% decode_runs(+Bytes, -Runs)
%% Decode run-length encoded byte pairs into run segments
%% Each pair: [ControlByte, SizeByte]
%% Run = run(Color, Length)
decode_runs([], []).
decode_runs([0x18 | _], []).     % Terminator
decode_runs([Control, Size | Rest], [run(Color, Length) | MoreRuns]) :-
    Control \= 0x18,
    % Decode color from bits 5-6
    ColorBits is (Control >> 5) /\ 3,
    decode_color(ColorBits, Color),
    % Decode length from bits 0-2 of control + full size byte
    Length is ((Control /\ 0x07) << 8) \/ Size,
    decode_runs(Rest, MoreRuns).

decode_color(0, none).
decode_color(1, red).
decode_color(2, green).
decode_color(3, both).

%% ============================================================================
%% Toggle Graphics
%% ============================================================================

%% toggle_graphics(+StateIn, -StateOut)
%% Toggle between radar image only and full overlay display
%% Original: if GraphicsOn then ShowPlane([0,1]) else ShowPlane([0..3])
toggle_graphics(
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, true, FB),
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, false, FB)
).
toggle_graphics(
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, false, FB),
    gfx_state(P, Func, Mask, CX, CY, XP, YP, XM, YM, CS, true, FB)
).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
