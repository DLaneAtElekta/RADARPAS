# Program Slicing Reconstruction of RADAR Control

## Overview

This document describes the program slicing methodology used to reconstruct the hypothetical "first state" of the RADARPAS terminal - the core RADAR control logic that would have existed before additional features were added.

## Slicing Criterion

**Primary criterion**: RADAR parameter control functionality
- Sending control commands (TiltUp, TiltDown, RangeUp, RangeDown, GainUp, GainDown)
- Receiving and parsing parameter responses
- RS232 serial communication with the remote RADAR unit

## Backward Slice Analysis

Starting from the `SendCom` procedure (the core command-sending function), we traced backward through data and control dependencies:

```
SendCom(Command, DelTime)
   ├── Tx('Z'), Tx(Command)  → RS232 transmission
   ├── Response variable     → SetParams procedure
   ├── Mode variable         → ModeType type
   ├── RT variable           → Real-time status
   ├── Delay()               → Turbo Pascal built-in
   ├── MsDos()               → RegisterType for timing
   └── WriteParams           → Parameter display
        └── Params           → ParamRec type
             ├── TiltType, RangeType, GainType
             └── TimeRec
```

## Components Included in Slice

### Types (lines 18-43 → reconstructed)
| Type | Purpose | Included |
|------|---------|----------|
| TiltType | Antenna tilt parameter range (0..11) | Yes |
| RangeType | Display range parameter (0..4) | Yes |
| GainType | Receiver gain (1..17) | Yes |
| ModeType | Operating mode | Simplified |
| TimeRec | Time from RADAR | Yes |
| RegisterType | DOS interrupt calls | Yes |
| ParamRec | Consolidated parameters | Yes (new) |

### Constants (lines 46-67 → reconstructed)
| Constant | Value | Purpose |
|----------|-------|---------|
| ComPort | $3F8 | COM1 serial port |
| TiltUp | #2 | Command code |
| TiltDown | #5 | Command code |
| RangeUp | #3 | Command code |
| RangeDown | #6 | Command code |
| GainUp | #13 | Command code |
| GainDown | #14 | Command code |
| OnOff | #1 | Power command |
| TiltVal[] | Lookup | Tilt degrees |
| RangeVal[] | Lookup | Range in km |

### Procedures (core slice)
| Procedure | Lines | Purpose | Included |
|-----------|-------|---------|----------|
| Tx | 857-861 | Transmit character | Yes |
| Rx | 863-872 | Receive from buffer | Yes |
| ResetBuf | 874-877 | Reset buffer | Yes |
| SendCom | 879-904 | **Core control** | Yes |
| SetParams | 906-939 | Parse Q response | Yes |
| RS232Interupt | 946-1053 | Interrupt handler | Simplified |
| InitRS232 | 1055-1073 | Serial init | Yes |
| ReadKbd | 153-160 | Keyboard input | Yes |
| WriteTime | 162-173 | Time display | Yes |
| WriteParams | 759-781 | Param display | Simplified |

## Components Removed from Slice

### Graphics System (lines 176-509)
- EGA initialization and palette setup
- Character tables (14x8, 8x8)
- Plane selection, function selection
- GRPlot, GRLine, GRWrite
- Window management
- Range mark circles
- Map overlay rendering

### Picture Reception (lines 1080-1200, 1689-1761)
- RxPicLoop procedure
- DispLine run-length decompression
- Picture file storage/retrieval
- 20KB picture buffer

### Map/Graphics Reception (lines 1650-1683)
- RxGraphLoop procedure
- MAP1.DAT, MAP2.DAT handling
- Coordinate system translation

### Station Management (lines 1204-1393)
- SelectStation procedure
- LoadStation procedure
- CallStation (modem dialing)
- Directory/file management

### Screen Dump (lines 1399-1484)
- ColorJetPrtSc
- EpsonMX80PrtSc
- Print interrupt handling

### Configuration (lines 1543-1606)
- Options menu
- Program file self-modification

### Complex UI (lines 514-825)
- Help overlay system
- Window system
- Storage browser

## Dependency Graph

```
                    ┌─────────────────┐
                    │   Main Loop     │
                    │ (F1-F6 keys)    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │    SendCom      │◄──── SLICING CRITERION
                    │ (send command)  │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼──────┐  ┌───────▼───────┐  ┌──────▼──────┐
    │     Tx      │  │   SetParams   │  │ WriteParams │
    │ (transmit)  │  │ (parse resp)  │  │  (display)  │
    └──────┬──────┘  └───────┬───────┘  └─────────────┘
           │                 │
    ┌──────▼──────┐  ┌───────▼───────┐
    │  ComPort    │  │  Q Protocol   │
    │   I/O       │  │   Decode      │
    └─────────────┘  └───────────────┘
```

## Protocol Details Preserved

### Command Format
```
Outbound: 'Z' + <command byte>
Examples:
  'Z' + #2  = Tilt Up
  'Z' + #5  = Tilt Down
  'Z' + #3  = Range Up
  'Z' + #6  = Range Down
```

### Response Format (Q response - 10 bytes)
```
Byte 1:   'Q' (response identifier)
Byte 2:   Gain (upper nibble)
Byte 3:   Tilt (lower nibble), RT flags (upper nibble)
Byte 4:   Range (bits 3-5)
Byte 5:   (reserved)
Bytes 6-9: Time as ASCII "HHMM"
Byte 10:  Checksum (sum of bytes 2-9)
```

## Reconstruction Notes

1. **Simplified ModeType**: Reduced from 5 modes to 2 (Disconnected, Interactive)
2. **Text-mode display**: Replaced EGA graphics with simple text output
3. **Consolidated ParamRec**: Combined scattered variables into single record
4. **Removed file I/O**: No picture storage or station files
5. **Removed modem handling**: Direct connection assumed

## File Listing

| File | Lines | Description |
|------|-------|-------------|
| 19880114 RADAR.PAS | 1,895 | Original full program |
| radar_control_v0.pas | ~350 | Reconstructed first state |

## Historical Context

The original program evolved from this core control logic to include:
1. **Phase 1**: Basic control (this reconstruction)
2. **Phase 2**: Picture reception and display
3. **Phase 3**: Map overlay support
4. **Phase 4**: Station management and modem dialing
5. **Phase 5**: File storage and retrieval
6. **Phase 6**: Screen printing and configuration

This reconstruction represents the hypothetical Phase 1 state.
