%% ============================================================================
%% RADARPAS Prolog Translation - RS232 Communication Module
%% ============================================================================
%% Translation of the RS-232 serial communication routines from RADAR.PAS.
%% Models the circular receive buffer, transmit/receive operations,
%% interrupt handler logic, and the SendCom command-response cycle.
%%
%% In Prolog, hardware I/O is modeled as state transformations on a
%% communication state structure rather than direct port access.
%%
%% Original: D. G. Lane, January 14, 1988
%% ============================================================================

:- module(rs232, [
    % State management
    make_rs232_state/1,
    rs232_mode/2,
    rs232_buffer/2,

    % Buffer operations
    reset_buffer/2,
    buffer_empty/1,
    buffer_push/3,
    buffer_pop/3,

    % Transmit / Receive
    tx/3,
    rx/3,

    % Command protocol
    send_command/4,

    % Interrupt handler (modeled as state transition)
    handle_interrupt/4,

    % Initialization
    init_rs232/2,

    % Connection management
    hang_up/2,
    call_station/4,

    % Modem commands
    modem_init_string/2,
    modem_dial_string/3,
    modem_response_meaning/2
]).

:- use_module(types).
:- use_module(protocol).

%% ============================================================================
%% RS232 State Structure
%% ============================================================================
%% rs232_state(Mode, Buffer, TxLog, ResponseBuf, Response, BaudRate, ComPort)
%%
%% Mode:        Current operating mode (modem/interactive/wait_pic/rx_pic/rx_graph)
%% Buffer:      Circular receive buffer (modeled as list)
%% TxLog:       Log of transmitted bytes (for verification)
%% ResponseBuf: Accumulator for building 10-byte responses
%% Response:    Whether last command got valid response
%% BaudRate:    Serial baud rate (default 2400)
%% ComPort:     COM port base address

make_rs232_state(rs232_state(modem, [], [], [], false, 2400, 0x3F8)).

rs232_mode(rs232_state(Mode, _, _, _, _, _, _), Mode).
rs232_buffer(rs232_state(_, Buf, _, _, _, _, _), Buf).

%% ============================================================================
%% Buffer Operations
%% ============================================================================
%% The original uses a circular buffer with BufBeg/BufEnd indices (1..255).
%% In Prolog, we model this as a simple list (queue semantics).

%% reset_buffer(+StateIn, -StateOut)
%% Clear the receive buffer
reset_buffer(
    rs232_state(Mode, _, Tx, _, Resp, Baud, Port),
    rs232_state(Mode, [], Tx, [], Resp, Baud, Port)
).

%% buffer_empty(+State)
%% True if buffer has no data
buffer_empty(rs232_state(_, [], _, _, _, _, _)).

%% buffer_push(+Byte, +StateIn, -StateOut)
%% Add byte to end of buffer (BufEnd position)
buffer_push(Byte,
    rs232_state(Mode, Buf, Tx, RBuf, Resp, Baud, Port),
    rs232_state(Mode, NewBuf, Tx, RBuf, Resp, Baud, Port)
) :-
    append(Buf, [Byte], NewBuf).

%% buffer_pop(+StateIn, -Byte, -StateOut)
%% Remove and return first byte from buffer (BufBeg position)
%% Returns 0 if buffer is empty (matching original Rx behavior)
buffer_pop(
    rs232_state(Mode, [Byte|Rest], Tx, RBuf, Resp, Baud, Port),
    Byte,
    rs232_state(Mode, Rest, Tx, RBuf, Resp, Baud, Port)
).
buffer_pop(
    rs232_state(Mode, [], Tx, RBuf, Resp, Baud, Port),
    0,
    rs232_state(Mode, [], Tx, RBuf, Resp, Baud, Port)
).

%% ============================================================================
%% Transmit / Receive
%% ============================================================================

%% tx(+Char, +StateIn, -StateOut)
%% Transmit single character (adds to TxLog)
%% Original: repeat until (port[ComPort+5] and $20)=$20; Port[ComPort]:=ord(Charac)
tx(Char,
    rs232_state(Mode, Buf, TxLog, RBuf, Resp, Baud, Port),
    rs232_state(Mode, Buf, NewTx, RBuf, Resp, Baud, Port)
) :-
    append(TxLog, [Char], NewTx).

%% rx(+StateIn, -Char, -StateOut)
%% Receive character from buffer (non-blocking)
%% Returns 0 if no data available
rx(State, Char, NewState) :-
    buffer_pop(State, Char, NewState).

%% ============================================================================
%% Interrupt Handler (State Transition Model)
%% ============================================================================
%% The original RS232Interupt procedure is a hardware interrupt handler
%% that processes incoming bytes based on the current operating mode.
%% In Prolog, we model this as a pure state transition.

%% handle_interrupt(+DataByte, +StateIn, -StateOut, -Action)
%% Process an incoming data byte according to current mode
%% Action describes any side-effect (parse_response, start_rx_pic, etc.)

% Modem mode: buffer incoming data
handle_interrupt(Data,
    rs232_state(modem, Buf, Tx, _, Resp, Baud, Port),
    rs232_state(modem, NewBuf, Tx, [], Resp, Baud, Port),
    buffered
) :-
    append(Buf, [Data], NewBuf).

% Interactive/WaitPic mode: accumulate response bytes
handle_interrupt(Data,
    rs232_state(Mode, Buf, Tx, RBuf, _, Baud, Port),
    NewState,
    Action
) :-
    (Mode = interactive ; Mode = wait_pic),
    append(RBuf, [Data], NewRBuf),
    length(NewRBuf, Len),
    (   Len =:= 10
    ->  % Full 10-byte response received - parse it
        (   parse_q_response(NewRBuf, Params)
        ->  Action = response_received(Params),
            NewState = rs232_state(Mode, Buf, Tx, [], true, Baud, Port)
        ;   Action = bad_response,
            NewState = rs232_state(Mode, Buf, Tx, [], false, Baud, Port)
        )
    ;   % Check for picture start sequence in WaitPic mode
        (   Mode = wait_pic,
            NewRBuf = [0xFF, 0xFE, 0xFD | _]
        ->  Action = start_rx_pic,
            NewState = rs232_state(rx_pic, Buf, Tx, [], false, Baud, Port)
        ;   Action = accumulating,
            NewState = rs232_state(Mode, Buf, Tx, NewRBuf, false, Baud, Port)
        )
    ).

% RxPic mode: accumulate picture data
handle_interrupt(Data,
    rs232_state(rx_pic, Buf, Tx, RBuf, _, Baud, Port),
    rs232_state(rx_pic, Buf, Tx, NewRBuf, false, Baud, Port),
    pic_data(Data)
) :-
    append(RBuf, [Data], NewRBuf).

% RxGraph mode: accumulate map overlay data
handle_interrupt(Data,
    rs232_state(rx_graph, Buf, Tx, RBuf, _, Baud, Port),
    NewState,
    Action
) :-
    append(RBuf, [Data], NewRBuf),
    length(NewRBuf, Len),
    (   Len =:= 9
    ->  % Check checksum on 8-byte block + checksum byte
        length(DataBytes, 8),
        append(DataBytes, [_ChkByte], NewRBuf),
        compute_checksum(DataBytes, _Computed),
        % Check for end-of-map marker (all zeros)
        (   DataBytes = [0, 0, 0, 0 | _]
        ->  Action = map_section_complete,
            NewState = rs232_state(rx_graph, Buf, Tx, [], false, Baud, Port)
        ;   Action = map_data(DataBytes),
            NewState = rs232_state(rx_graph, Buf, Tx, [], false, Baud, Port)
        )
    ;   Action = accumulating,
        NewState = rs232_state(rx_graph, Buf, Tx, NewRBuf, false, Baud, Port)
    ).

%% ============================================================================
%% SendCom - Core Command/Response Cycle
%% ============================================================================
%% Original: procedure SendCom(Command : char; DelTime : integer)
%%
%% Sends command ('Z' + CommandByte), waits for response with timeout.
%% In Prolog, we model this as a state transformation assuming the
%% response is provided (since we can't do real hardware I/O).

%% send_command(+CommandName, +ResponseBytes, +StateIn, -StateOut)
%% Send command and process response
%% ResponseBytes is the 10-byte response (or [] if timeout)
send_command(CommandName, ResponseBytes,
    rs232_state(interactive, Buf, Tx, _, _, Baud, Port),
    rs232_state(interactive, Buf, NewTx, [], GotResponse, Baud, Port)
) :-
    % Format command bytes
    format_command(CommandName, CmdBytes),
    append(Tx, CmdBytes, NewTx),

    % Process response
    (   ResponseBytes \= [],
        parse_q_response(ResponseBytes, _Params)
    ->  GotResponse = true
    ;   GotResponse = false
    ).

% SendCom is a no-op if not in Interactive mode
send_command(_, _, State, State) :-
    rs232_mode(State, Mode),
    Mode \= interactive.

%% ============================================================================
%% Initialization
%% ============================================================================

%% init_rs232(+ComPort, -State)
%% Initialize RS-232 port and create initial state
%% Original: procedure InitRS232
%% Configures: 2400 baud, 8 data bits, 1 stop bit, no parity
init_rs232(ComPort,
    rs232_state(modem, [], [], [], false, 2400, ComPort)
).

%% ============================================================================
%% Connection Management
%% ============================================================================

%% hang_up(+StateIn, -StateOut)
%% Terminate modem connection (DTR low, then DTR high)
%% Original: Port[ComPort+4]:=$08; Delay(1000); Port[ComPort+4]:=$0B
hang_up(
    rs232_state(_, Buf, Tx, RBuf, Resp, Baud, Port),
    rs232_state(modem, Buf, Tx, RBuf, Resp, Baud, Port)
).

%% call_station(+PhoneNum, +ModemType, +StateIn, -StateOut)
%% Dial phone number to connect to radar station
%% Original: procedure CallStation
call_station(PhoneNum, ModemType, StateIn, StateOut) :-
    modem_dial_string(ModemType, PhoneNum, DialStr),
    % Transmit dial string byte by byte
    atom_codes(DialStr, Codes),
    foldl(tx, Codes, StateIn, StateOut).

%% ============================================================================
%% Modem Configuration
%% ============================================================================

%% modem_init_string(+ModemType, -InitString)
%% Modem initialization command string
%% 0 = Hayes compatible, 1 = Racal-Vadic
modem_init_string(0, 'AT &F &C1 &D2 L M1 E V X4\r').
modem_init_string(1, '\x05\r\x05\rO21122211211111112112\r').

%% modem_dial_string(+ModemType, +PhoneNum, -DialString)
%% Format modem dial command
modem_dial_string(0, PhoneNum, DialStr) :-
    atom_concat('ATDT', PhoneNum, Temp),
    atom_concat(Temp, '\r', DialStr).
modem_dial_string(1, PhoneNum, DialStr) :-
    atom_concat('D', PhoneNum, Temp),
    atom_concat(Temp, '\r', DialStr).

%% modem_response_meaning(+ResponseChar, -Meaning)
%% Decode modem response characters
%% Original: case ModemMess of '1','L' -> CONNECTED; etc.
modem_response_meaning(0'1, connected_2400).
modem_response_meaning(0'L, connected_2400).
modem_response_meaning(0'3, no_carrier).
modem_response_meaning(0'4, modem_error).
modem_response_meaning(0'C, modem_error).
modem_response_meaning(0'6, no_dial_tone).
modem_response_meaning(0'E, no_dial_tone).
modem_response_meaning(0'7, busy).
modem_response_meaning(0'B, busy).
modem_response_meaning(0'8, no_answer).
modem_response_meaning(0'F, no_answer).
modem_response_meaning(0'T, timeout).
modem_response_meaning(0'A, answer_tone).
modem_response_meaning(0'D, dialing).
modem_response_meaning(0'R, ringing).

%% ============================================================================
%% END OF MODULE
%% ============================================================================
