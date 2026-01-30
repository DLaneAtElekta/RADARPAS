%% ============================================================================
%% RADARPAS Prolog Translation - Protocol Module
%% ============================================================================
%% Translation of the RS-232 protocol handling from RADAR.PAS
%% Covers the SetParams procedure and Q response parsing.
%%
%% The Ellason E300 RADAR communicates via a 10-byte 'Q' response:
%%   Byte 1:    'Q' (0x51) - Response identifier
%%   Byte 2:    Gain (upper nibble)
%%   Byte 3:    Tilt (lower nibble), RT flags (upper nibble)
%%   Byte 4:    Range (bits 3-5)
%%   Byte 5:    Reserved
%%   Bytes 6-9: Time as ASCII "HHMM"
%%   Byte 10:   Checksum (sum of bytes 2-9)
%%
%% Commands are sent as: 'Z' + <command byte>
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(protocol, [
    % Q response parsing
    parse_q_response/2,
    validate_checksum/1,

    % Command formatting
    format_command/2,
    command_prefix/1,

    % Parameter decoding
    decode_gain/2,
    decode_tilt/2,
    decode_range/2,
    decode_time/3,
    decode_rt_status/2,

    % Response types
    is_q_response/1,
    is_g_response/1,

    % Checksum
    compute_checksum/2
]).

:- use_module(types).

%% ============================================================================
%% Command Formatting
%% ============================================================================

%% command_prefix(?Prefix)
%% All commands are prefixed with 'Z' (0x5A)
command_prefix(0x5A).

%% format_command(+CommandName, -Bytes)
%% Format a command for transmission: ['Z', CommandByte]
format_command(CommandName, [0x5A, Code]) :-
    command_code(CommandName, Code).

%% ============================================================================
%% Checksum Computation
%% ============================================================================

%% compute_checksum(+ByteList, -Checksum)
%% Sum of bytes mod 256 (8-bit checksum)
compute_checksum(Bytes, Checksum) :-
    sum_list(Bytes, Sum),
    Checksum is Sum mod 256.

%% validate_checksum(+ResponseBytes)
%% Verify that byte 10 equals sum of bytes 2-9
%% ResponseBytes is a list of 10 bytes
validate_checksum(ResponseBytes) :-
    length(ResponseBytes, 10),
    nth1(10, ResponseBytes, Expected),
    % Extract bytes 2-9
    ResponseBytes = [_ | Rest9],
    length(DataBytes, 8),
    append(DataBytes, [_], Rest9),
    compute_checksum(DataBytes, Expected).

%% ============================================================================
%% Response Type Detection
%% ============================================================================

%% is_q_response(+ResponseBytes)
%% True if first byte is 'Q' (0x51 = 81)
is_q_response([0x51 | _]).

%% is_g_response(+ResponseBytes)
%% True if first byte is 'G' (0x47 = 71)
is_g_response([0x47 | _]).

%% ============================================================================
%% Parameter Decoding
%% ============================================================================

%% decode_gain(+Byte2, -Gain)
%% Gain = (Byte2 >> 4) + 1
%% Byte 3 bit 5 set means Gain = 17 (PRE mode)
decode_gain(Byte2, Gain) :-
    Gain is (Byte2 >> 4) + 1.

%% decode_tilt(+Byte3, -Tilt)
%% Tilt = 12 - (Byte3 AND 0x0F)
decode_tilt(Byte3, Tilt) :-
    Tilt is 12 - (Byte3 /\ 0x0F).

%% decode_range(+Byte4, -RangeIndex)
%% Decode range from bits 3-5 of byte 4
%% Pattern mapping from original Pascal case statement
decode_range(Byte4, RangeIndex) :-
    Bits is Byte4 /\ 0x38,
    decode_range_bits(Bits, RangeIndex).

decode_range_bits(0x28, 0).   % 10 km
decode_range_bits(0x08, 1).   % 25 km
decode_range_bits(0x30, 2).   % 50 km
decode_range_bits(0x00, 3).   % 100 km
decode_range_bits(0x20, 4).   % 200 km

%% decode_time(+Byte6, +Byte7_8_9, -TimeRec)
%% Time encoded as ASCII digits: Bytes 6-9 = "HHMM"
%% Each byte is an ASCII digit (48-57)
decode_time([B6, B7, B8, B9], Hour, Minute) :-
    Hour is (B6 - 48) * 10 + (B7 - 48),
    Minute is (B8 - 48) * 10 + (B9 - 48).

%% decode_rt_status(+Byte3, -RTStatus)
%% Decode Real-Time status from byte 3 flag bits
%% Bit 7 clear -> RT=2 (active)
%% Bit 7 set, Bit 4 clear -> RT=0 (off)
%% Bit 7 set, Bit 4 set -> RT=1 (on)
decode_rt_status(Byte3, RT) :-
    (   (Byte3 /\ 0x80) =:= 0
    ->  RT = 2
    ;   (Byte3 /\ 0x10) =:= 0
    ->  RT = 0
    ;   RT = 1
    ).

%% ============================================================================
%% Q Response Parsing (SetParams)
%% ============================================================================

%% parse_q_response(+ResponseBytes, -Params)
%% Parse a 10-byte Q response into a parameter structure
%% Params = params(Gain, Tilt, Range, Hour, Minute, RT)
%%
%% Corresponds to the Pascal SetParams procedure
parse_q_response(ResponseBytes, params(FinalGain, Tilt, Range, Hour, Minute, RT)) :-
    % Validate it's a Q response with correct checksum
    is_q_response(ResponseBytes),
    validate_checksum(ResponseBytes),

    % Extract individual bytes
    ResponseBytes = [_Q, B2, B3, B4, _B5, B6, B7, B8, B9, _Chk],

    % Decode gain from byte 2 upper nibble
    decode_gain(B2, BaseGain),

    % Check for PRE-amplifier mode (bit 5 of byte 3)
    (   (B3 /\ (1 << 5)) =\= 0
    ->  FinalGain = 17
    ;   FinalGain = BaseGain
    ),

    % Decode tilt from byte 3 lower nibble
    decode_tilt(B3, Tilt),

    % Decode range from byte 4
    decode_range(B4, Range),

    % Decode time from bytes 6-9
    decode_time([B6, B7, B8, B9], Hour, Minute),

    % Decode RT status from byte 3
    decode_rt_status(B3, RT).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
