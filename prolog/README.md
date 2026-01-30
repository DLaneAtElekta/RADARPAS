# RADARPAS Prolog Translation

Prolog translation of the RADARPAS (Ellason E300 Radar Terminal) system,
originally written in Turbo Pascal (1988) by D. G. Lane.

## Overview

This translation renders the original Pascal program's types, data structures,
protocol handling, state machines, and control logic as declarative Prolog
predicates. Hardware-specific operations (EGA graphics, RS-232 port I/O,
DOS interrupts) are modeled as state transformations rather than direct
hardware access.

## Requirements

- [SWI-Prolog](https://www.swi-prolog.org/) 8.0 or later

## Quick Start

```sh
cd prolog
swipl -l src/radar_terminal.pl
```

```prolog
?- start.           % Launch terminal (displays banner and initial state)
?- run_tests.       % Run self-verification tests
?- list_modules.    % Show module summary
```

## Module Structure

| File | Module | Purpose |
|------|--------|---------|
| `src/types.pl` | `types` | Core type definitions, constants, lookup tables (TiltType, RangeType, GainType, ModeType, command codes, EGA palette) |
| `src/protocol.pl` | `protocol` | RS-232 protocol: Q response parsing, checksum, command formatting, parameter decoding |
| `src/rs232.pl` | `rs232` | Serial communication: circular buffer, tx/rx, interrupt handler model, SendCom, modem control |
| `src/graphics.pl` | `graphics` | EGA graphics: plane/function/mask selection, pixel plotting, line drawing, RLE decompression, window management |
| `src/screen.pl` | `screen` | Display formatting: parameter display, time formatting, help text, range circles, map overlays |
| `src/storage.pl` | `storage` | Picture file management: catalog, save/load, filename generation, storage menu |
| `src/stations.pl` | `stations` | Station directory: select/add/delete stations, phone numbers, map data loading |
| `src/main.pl` | `main` | Main control logic: modem/interactive/rx_pic state machines, key mapping, event processing |
| `src/radar_terminal.pl` | (entry point) | Top-level loader, self-test suite, module summary |

## Architecture

The translation follows these principles:

1. **Types as validation predicates** - Pascal subrange types (`0..11`) become
   Prolog predicates (`valid_tilt/1`) that validate values
2. **Records as compound terms** - Pascal records become Prolog terms with
   accessor predicates (e.g., `pic_rec(FileName, FileDate, ...)`)
3. **State machines as state transformations** - The three main loops
   (ModemLoop, InterLoop, RxPicLoop) are modeled as `process_event/3`
   predicates that transform application state
4. **Hardware I/O as abstract operations** - EGA port writes, RS-232 interrupts,
   and DOS calls are modeled as state changes recorded in operation logs
5. **Lookup tables as facts** - Pascal constant arrays become Prolog facts
   (e.g., `tilt_value(Index, Degrees)`)

## Correspondence to Original Pascal

| Pascal | Prolog |
|--------|--------|
| `Program Radar_Terminal` | `radar_terminal.pl` (entry point) |
| `type TiltType = 0..11` | `valid_tilt/1` in `types.pl` |
| `const TiltVal: array[...]` | `tilt_value/2` facts in `types.pl` |
| `procedure SetParams` | `parse_q_response/2` in `protocol.pl` |
| `procedure SendCom` | `send_command/4` in `rs232.pl` |
| `procedure RS232Interupt` | `handle_interrupt/4` in `rs232.pl` |
| `procedure InitRS232` | `init_rs232/2` in `rs232.pl` |
| `procedure DispLine` | `disp_line/4` in `graphics.pl` |
| `procedure WriteParams` | `write_params/3` in `screen.pl` |
| `procedure WriteRngMks` | `write_range_marks/2` in `screen.pl` |
| `procedure WriteGfx` | `write_gfx/3` in `screen.pl` |
| `procedure SavePic` | `save_pic/3` in `storage.pl` |
| `procedure FetchPic` | `fetch_pic/2` in `storage.pl` |
| `procedure LoadStation` | `load_station/3` in `stations.pl` |
| `procedure SelectStation` | `select_station/3` in `stations.pl` |
| `procedure ExecCom` | `exec_command/3` in `main.pl` |
| `procedure InterLoop` | `interactive_event/3` in `main.pl` |
| `procedure ModemLoop` | `modem_event/3` in `main.pl` |
| `procedure RxPicLoop` | `rx_pic_event/3` in `main.pl` |

## Protocol Details

The Ellason E300 RADAR communicates via RS-232 at 2400 baud (8N1):

**Command format:** `Z` + command byte

| Command | Code | Description |
|---------|------|-------------|
| TiltUp | 2 | Increase antenna tilt angle |
| TiltDown | 5 | Decrease antenna tilt angle |
| RangeUp | 3 | Increase radar range |
| RangeDown | 6 | Decrease radar range |
| GainUp | 13 | Increase receiver gain |
| GainDown | 14 | Decrease receiver gain |
| SendPic | 4 | Request picture transfer |
| CheckGraph | 16 | Check map overlay version |
| SendGraph | 10 | Request map overlay transfer |

**Q Response (10 bytes):**

| Byte | Content |
|------|---------|
| 1 | `Q` (0x51) identifier |
| 2 | Gain (upper nibble) |
| 3 | Tilt (lower nibble) + RT flags (upper nibble) |
| 4 | Range (bits 3-5) |
| 5 | Reserved |
| 6-9 | Time as ASCII "HHMM" |
| 10 | Checksum (sum of bytes 2-9) |

## License

Original software Copyright (C) 1987 D. G. Lane. All rights reserved.
