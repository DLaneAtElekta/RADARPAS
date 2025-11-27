{****************************************************************************}
{* RADAR CONTROL - Reconstructed First State                               *}
{*                                                                         *}
{* Program slicing reconstruction of the original RADAR terminal's core    *}
{* control logic, before picture reception, map overlays, station mgmt,    *}
{* file storage, and EGA graphics were added.                              *}
{*                                                                         *}
{* Slicing criterion: RADAR parameter control (Tilt/Range/Gain Up/Down)    *}
{*                                                                         *}
{* Original: D. G. Lane, circa 1987                                        *}
{* Reconstructed: 2025 via program slicing                                 *}
{****************************************************************************}

{$C-,V-,I-,R-,U-,K-}

Program Radar_Control;

{============================================================================}
{= Core Type Definitions                                                    =}
{============================================================================}
type
  TiltType         = 0..11;
  RangeType        = 0..4;
  GainType         = 1..17;

  ModeType         = (Disconnected, Interactive);

  TimeRec          = record
    Hour           :   0..23;
    Minute         :   0..59;
  end;

  RegisterType     = record
    case integer of
      1 : (AX,BX,CX,DX,BP,DI,SI,DS,ES,Flags : integer);
      2 : (AL,AH,BL,BH,CL,CH,DL,DH          : byte);
  end;

  ParamRec         = record
    Time           :   TimeRec;
    Tilt           :   TiltType;
    Range          :   RangeType;
    Gain           :   GainType;
  end;

{============================================================================}
{= Constants - Command Codes for Ellason E300 RADAR                         =}
{============================================================================}
const
  { Serial port configuration }
  ComPort          : integer = $3F8;   { COM1 base address }

  { RADAR Control Commands }
  { These are the core command codes sent to the remote RADAR unit }
  OnOff            = #1;               { Power on/off }
  TiltUp           = #2;               { Increase antenna tilt angle }
  RangeUp          = #3;               { Increase display range }
  TiltDown         = #5;               { Decrease antenna tilt angle }
  RangeDown        = #6;               { Decrease display range }
  GainUp           = #13;              { Increase receiver gain }
  GainDown         = #14;              { Decrease receiver gain }

  { Parameter value lookup tables }
  TiltVal          : array[TiltType] of byte =
                       (0,1,2,3,4,5,6,8,10,12,15,20);
  RangeVal         : array[RangeType] of byte =
                       (10,25,50,100,200);

{============================================================================}
{= Global Variables                                                         =}
{============================================================================}
var
  { Current RADAR parameters }
  Params           : ParamRec;
  RT               : byte;             { Real-time mode flag }

  { Operating mode }
  Mode             : ModeType;

  { RS232 Receive Buffer (circular) }
  Buf              : string[255];
  BufBeg, BufEnd   : integer;

  { Protocol state }
  CheckSum         : byte;
  Response         : boolean;

  { System }
  Registers        : RegisterType;
  DSave            : integer absolute CSeg:$0006;
  Key              : char;
  Escape           : boolean;
  I                : integer;

{============================================================================}
{= Keyboard Input                                                           =}
{============================================================================}
procedure ReadKbd;
begin
  Read(Kbd, Key);
  if KeyPressed then begin
    Read(Kbd, Key);
    Escape := true;
  end else
    Escape := false;
end;

{============================================================================}
{= Display Routines (Text Mode)                                             =}
{============================================================================}
procedure WriteTime(Time : TimeRec);
begin
  if Time.Hour < 10 then Write('0');
  Write(Time.Hour, ':');
  if Time.Minute < 10 then Write('0');
  Write(Time.Minute);
end;

procedure WriteParams;
begin
  GotoXY(1, 5);
  Write('  TILT  : ', TiltVal[Params.Tilt]:3, ' degrees     ');
  GotoXY(1, 6);
  Write('  RANGE : ', RangeVal[Params.Range]:3, ' km         ');
  GotoXY(1, 7);
  if Params.Gain < 17 then
    Write('  GAIN  : ', Params.Gain:3, '              ')
  else
    Write('  GAIN  : PRE              ');
  GotoXY(1, 8);
  Write('  TIME  : '); WriteTime(Params.Time); Writeln('      ');
  GotoXY(1, 9);
  case RT of
    0   : Write('  RT    : OFF       ');
    1,2 : Write('  RT    : ON        ');
  end;
end;

procedure WriteStatus(Msg : string);
begin
  GotoXY(1, 15);
  Write(Msg, '                              ');
end;

procedure WriteHelp;
begin
  GotoXY(1, 11);
  Writeln('  --------------------------------');
  Writeln('  F1 - Tilt Up     F2 - Tilt Down');
  Writeln('  F3 - Range Up    F4 - Range Down');
  Writeln('  F5 - Gain Up     F6 - Gain Down');
  Writeln('  ESC - Quit');
end;

{============================================================================}
{= RS232 Communication - Core Serial I/O                                    =}
{============================================================================}

{ Transmit single character }
procedure Tx(Charac : char);
begin
  repeat until (port[ComPort+5] and $20) = $20;
  Port[ComPort] := ord(Charac);
end;

{ Receive character from buffer (non-blocking) }
procedure Rx(var Charac : char);
begin
  if BufBeg = BufEnd then
    Charac := #0
  else begin
    Charac := Buf[BufBeg];
    BufBeg := BufBeg + 1;
    if BufBeg > 255 then BufBeg := 1;
  end;
end;

{ Reset receive buffer }
procedure ResetBuf;
begin
  BufBeg := 1;
  BufEnd := 1;
end;

{============================================================================}
{= Protocol Handling                                                        =}
{============================================================================}

{ Parse parameter response from RADAR ('Q' response) }
procedure SetParams(var ForBuf; var OutParams : ParamRec);
var
  RxBuf : string[10] absolute ForBuf;
begin
  CheckSum := 0;
  for I := 2 to 9 do
    CheckSum := CheckSum + Ord(RxBuf[I]);

  Response := CheckSum = Ord(RxBuf[10]);

  if (RxBuf[1] = 'Q') and Response then
    with OutParams do begin
      { Decode Gain: upper nibble of byte 2, +1 }
      Gain := (byte(RxBuf[2]) shr 4) + 1;

      { Decode Tilt: lower nibble of byte 3, inverted from 12 }
      Tilt := 12 - (byte(RxBuf[3]) and $0F);

      { Check for PRE-amplifier mode (bit 5 of byte 3) }
      if (byte(RxBuf[3]) and (1 shl 5)) <> 0 then
        Gain := 17;

      { Decode Range from byte 4 bit pattern }
      case (byte(RxBuf[4]) and $38) of
        $08 : Range := 1;   { 25 km }
        $30 : Range := 2;   { 50 km }
        $00 : Range := 3;   { 100 km }
        $20 : Range := 4;   { 200 km }
        $28 : Range := 0;   { 10 km }
      end;

      { Decode Time from ASCII bytes 6-9 }
      Time.Hour := (ord(RxBuf[6]) - 48) * 10 + (ord(RxBuf[7]) - 48);
      Time.Minute := (ord(RxBuf[8]) - 48) * 10 + (ord(RxBuf[9]) - 48);

      { Decode RT (Real-Time) status from byte 3 }
      if (byte(RxBuf[3]) and $80) = $00 then
        RT := 2
      else if (byte(RxBuf[3]) and $10) = $00 then
        RT := 0
      else
        RT := 1;
    end;

  RxBuf := '';
end;

{============================================================================}
{= RS232 Interrupt Handler                                                  =}
{============================================================================}
var
  data : byte;

procedure RS232Interupt;
begin
  inline($1E/       {PUSH DS}
         $50/       {PUSH AX}
         $53/       {PUSH BX}
         $51/       {PUSH CX}
         $52/       {PUSH DX}
         $57/       {PUSH DI}
         $56/       {PUSH SI}
         $06/       {PUSH ES}
         $8C/$C8/   {MOV AX,CS}
         $8E/$D8/   {MOV DS,AX}
         $A1/DSave/ {MOV AX,DSave}
         $8E/$D8/$FB);  {MOV DS,AX}

  if port[ComPort+2] = $04 then begin
    data := port[ComPort];
    port[$20] := $20; {EOI for 8259}

    case Mode of
      Disconnected:
        begin
          { Buffer incoming data in disconnected mode }
          Buf[BufEnd] := chr(data);
          BufEnd := BufEnd + 1;
          if BufEnd > 255 then BufEnd := 1;
        end;

      Interactive:
        begin
          { Collect response bytes }
          Buf := Buf + chr(data);
          { When we have 10 bytes, parse the Q response }
          if Length(Buf) = 10 then begin
            SetParams(Buf, Params);
            Delay(10);
            Tx('A');  { Send acknowledgment }
            Buf := '';
          end;
        end;
    end;
  end
  else begin
    { Handle modem status change (carrier detect) }
    if port[ComPort+2] = $00 then
      if (port[ComPort+6] and $88) = $08 then
        Mode := Disconnected;
    port[$20] := $20;
  end;

  inline($07/       {POP ES}
         $5E/       {POP SI}
         $5F/       {POP DI}
         $5A/       {POP DX}
         $59/       {POP CX}
         $5B/       {POP BX}
         $58/       {POP AX}
         $1F);      {POP DS}
  inline($FB);      {STI}
  inline($CF);      {IRET}
end;

{============================================================================}
{= RS232 Initialization                                                     =}
{============================================================================}
procedure InitRS232;
begin
  DSave := DSeg;
  Buf := '';

  { Install interrupt handler }
  with Registers do begin
    AH := $25;
    if ComPort = $3F8 then AL := $0C else AL := $0B;
    DX := Ofs(RS232Interupt) + 7;
    DS := CSeg;
    Intr($21, Registers);
  end;

  { Clear any pending data }
  for I := ComPort to ComPort + 6 do
    data := port[I];

  { Configure serial port: 2400 baud, 8N1 }
  Port[ComPort+3] := $80;   { Set baud rate access bit }
  Port[ComPort] := 48;      { Baud rate divisor (2400) }
  Port[ComPort+1] := $00;
  Port[ComPort+3] := $03;   { 8 data bits, 1 stop, no parity }
  Port[ComPort+1] := $09;   { Enable receive & modem status interrupts }
  Port[ComPort+4] := $0B;   { DTR & RTS high }

  { Enable IRQ in 8259 PIC }
  if ComPort = $3F8 then
    port[$21] := port[$21] and not(1 shl 4)
  else
    port[$21] := port[$21] and not(1 shl 3);
end;

{============================================================================}
{= CORE CONTROL LOGIC - SendCom                                             =}
{= This is the heart of the RADAR control - sends a command and waits      =}
{= for the response containing updated parameters.                          =}
{============================================================================}
procedure SendCom(Command : char; DelTime : integer);
var
  StartTime, CurrTime : integer;
begin
  if Mode = Interactive then begin
    Buf := '';
    Response := false;

    { Send command: 'Z' prefix + command byte }
    Tx('Z');
    Delay(15);
    Tx(Command);

    { If not in real-time mode, wait for antenna movement }
    if (RT = 0) then
      Delay(1000);

    { Wait for response with timeout }
    with Registers do begin
      AH := $2C;
      MsDos(Registers);
      StartTime := DH * 100 + DL;

      repeat
        AH := $2C;
        MsDos(Registers);
        CurrTime := DH * 100 + DL;
        if CurrTime < StartTime then
          CurrTime := CurrTime + 6000;  { Handle minute rollover }
      until (CurrTime - StartTime > DelTime) or Response;
    end;

    { Update display or signal error }
    if Response then
      WriteParams
    else begin
      Sound(440);
      Delay(10);
      NoSound;
      WriteStatus('No response from RADAR');
    end;
  end;
end;

{============================================================================}
{= Main Interactive Control Loop                                            =}
{============================================================================}
procedure InteractiveLoop;
begin
  WriteHelp;

  { Initialize parameters display }
  Params.Tilt := 6;
  Params.Range := 2;
  Params.Gain := 8;
  Params.Time.Hour := 0;
  Params.Time.Minute := 0;
  RT := 0;

  { Query current status }
  Buf := '';
  SendCom('X', 150);
  if not Response then SendCom('X', 150);
  if not Response then SendCom('X', 150);

  if not Response then begin
    WriteStatus('No response - check connection');
  end else begin
    WriteStatus('Connected - Ready');
  end;

  { Main control loop }
  repeat
    ReadKbd;

    if Escape then begin
      case Key of
        #59 : begin  { F1 - Tilt Up }
                WriteStatus('Tilt Up...');
                SendCom(TiltUp, 150);
              end;
        #60 : begin  { F2 - Tilt Down }
                WriteStatus('Tilt Down...');
                SendCom(TiltDown, 150);
              end;
        #61 : begin  { F3 - Range Up }
                WriteStatus('Range Up...');
                SendCom(RangeUp, 300);
              end;
        #62 : begin  { F4 - Range Down }
                WriteStatus('Range Down...');
                SendCom(RangeDown, 300);
              end;
        #63 : begin  { F5 - Gain Up }
                WriteStatus('Gain Up...');
                SendCom(GainUp, 150);
              end;
        #64 : begin  { F6 - Gain Down }
                WriteStatus('Gain Down...');
                SendCom(GainDown, 150);
              end;
      end;
    end;

  until Key = #27;  { ESC to exit }
end;

{============================================================================}
{= Cleanup                                                                  =}
{============================================================================}
procedure DeInit;
begin
  port[ComPort+4] := $08;   { DTR & RTS off }
  port[ComPort+1] := $00;   { Disable interrupts }
  port[$21] := port[$21] or (1 shl 4);  { Disable IRQ }
end;

{============================================================================}
{= Main Program                                                             =}
{============================================================================}
begin
  ClrScr;
  Writeln;
  Writeln('  ======================================');
  Writeln('    RADAR CONTROL - First State');
  Writeln('    Ellason E300 Parameter Controller');
  Writeln('  ======================================');
  Writeln;

  Mode := Interactive;
  ResetBuf;
  InitRS232;

  InteractiveLoop;

  DeInit;
  ClrScr;
end.
