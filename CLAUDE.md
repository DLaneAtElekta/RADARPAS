# CLAUDE.md - AI Assistant Guide for RADARPAS

## Project Overview

RADARPAS is a **historical software preservation project** containing Pascal source code from 1988 for the Ellason E300/E250 weather radar terminal system. The project demonstrates:

- **Original Code** (1988): Turbo Pascal 3.0+ for MS-DOS with direct hardware access
- **Modern Port** (2024): FreePascal-compatible version with stubbed hardware features
- **Program Slicing**: Reconstructed first-state control logic via program slicing methodology

This is NOT active development software - it's a preservation and educational project.

## Directory Structure

```
RADARPAS/
├── 19880114 RADAR.PAS          # Original 1988 Turbo Pascal source (1,894 lines)
├── radar.pas                   # FreePascal-compatible modern port (370 lines)
├── radar_control_v0.pas        # Program-sliced reconstruction (483 lines)
├── knowledge_base.pl           # Prolog knowledge base with ontology metadata
├── Dockerfile                  # Ubuntu 22.04 + FreePascal container
├── Makefile                    # Build automation
├── build.sh                    # One-command Docker build script
├── README.md                   # Project documentation
├── BUILD.md                    # Build instructions
├── PROGRAM_SLICING.md          # Program slicing methodology
├── documents/                  # Historical documentation and PDFs
│   ├── 19880114 RADAR.PAS      # Copy of original source
│   └── *.pdf                   # Historical notes
└── .github/workflows/
    └── build.yml               # GitHub Actions CI/CD
```

## Key Files and Their Purpose

| File | Purpose | AI Should Know |
|------|---------|----------------|
| `radar.pas` | Modern FreePascal port | This is the compilable version |
| `19880114 RADAR.PAS` | Historical original | Read-only, for reference |
| `radar_control_v0.pas` | Sliced control logic | Shows core control flow |
| `knowledge_base.pl` | Semantic metadata | Rich ontology-aligned facts |
| `Makefile` | Build configuration | Uses `fpc` with `-Mtp` mode |

## Build System

### Quick Commands

```bash
# Automated Docker build (recommended)
./build.sh

# Manual Docker build
docker build -t radarpas-fpc:latest .
docker run --rm -v "$(pwd):/build" radarpas-fpc:latest make

# Run the program
docker run --rm -it -v "$(pwd):/build" radarpas-fpc:latest ./radarpas

# Make targets
make           # Build radarpas binary
make run       # Build and run
make clean     # Remove build artifacts
make info      # Show compiler info
make help      # Show available targets
```

### Compiler Configuration

- **Compiler**: FreePascal (fpc) 3.2.0+
- **Mode**: Turbo Pascal compatibility (`-Mtp` / `{$MODE TP}`)
- **Flags**: `-Mtp -O2 -vh -l`
- **Container**: Ubuntu 22.04 base

### CI/CD

GitHub Actions runs on every push:
1. Native FreePascal build on Ubuntu
2. Docker container build verification
3. Non-interactive test run
4. Binary artifact upload

## Technical Architecture

### Original System Modules (1988)

```
RADARPAS
├── Miscellaneous Routines (lines 1-70)
│   └── DOS interface, file operations, keyboard I/O
├── Graphics Routines (lines 176-512)
│   └── EGA rendering, character tables, plane selection
├── Screen Format Routines (lines 513-823)
│   └── UI layout, range circles, map overlays
├── RS232 Routines (lines 857-1074)
│   └── Serial communication, modem protocol, interrupts
├── Storage Routines (lines 1080-1200)
│   └── Picture file management, metadata handling
├── Screen Dump (printer support)
├── Initialization/Configuration
└── Main Control Loops (lines 1689-1894)
```

### Key Types

```pascal
TiltType   = 0..11;     // Antenna tilt angle
RangeType  = 0..4;      // Radar range (10-200 km)
GainType   = 1..17;     // Receiver gain (17 = PRE-amplifier)
ModeType   = (Modem, Interactive, WaitPic, RxPic, RxGraph);
```

### Protocol Commands

| Command | Byte | Purpose |
|---------|------|---------|
| TiltUp | #2 | Increase antenna tilt |
| TiltDown | #5 | Decrease antenna tilt |
| RangeUp | #3 | Increase range |
| RangeDown | #6 | Decrease range |
| GainUp | #13 | Increase gain |
| GainDown | #14 | Decrease gain |
| OnOff | #1 | Power toggle |

### Q Response Protocol (10 bytes)

```
Byte 1:   'Q' (response identifier)
Byte 2:   Gain (upper nibble)
Byte 3:   Tilt (lower nibble), RT flags (upper nibble)
Byte 4:   Range (bits 3-5)
Byte 5:   Reserved
Bytes 6-9: Time as ASCII "HHMM"
Byte 10:  Checksum (sum of bytes 2-9)
```

## Code Conventions

### Pascal Syntax (Turbo Pascal / FreePascal)

- Uses `{$MODE TP}` for Turbo Pascal compatibility
- Assembly uses `{$ASMMODE INTEL}` directive
- Hardware access via `port[]` (stubbed in modern version)
- Direct memory via `Mem[]` (stubbed in modern version)

### Naming Conventions

- **Procedures**: PascalCase (`SendCom`, `SetParams`, `InitRS232`)
- **Variables**: PascalCase (`BufBeg`, `CurrPic`, `StationName`)
- **Types**: PascalCase with suffix (`TiltType`, `ModeType`, `TimeRec`)
- **Constants**: PascalCase or UPPERCASE (`ComPort`, `TiltUp`)

### Important Notes for Modifications

1. **DO NOT modify** `19880114 RADAR.PAS` - it's historical record
2. **DO NOT add** hardware dependencies to `radar.pas` - keep it buildable
3. Preserve the `{$MODE TP}` directive for compatibility
4. Keep stub procedures for hardware access (graphics, serial I/O)
5. The date comment at top should be updated if changes are made:
   ```pascal
   (**********************************)
   (* DID YOU JUST CHANGE SOMETHING? *)
   (*                                *)
   (*    IF SO, CHANGE THE DATE!!!   *)
   (*           ---------------      *)
   (**********************************)
   ```

## Knowledge Base (Prolog)

The `knowledge_base.pl` file contains semantic metadata aligned with:

- **Dublin Core (DC)**: Resource metadata
- **IAO**: Information artifacts
- **SSN/SOSA**: Sensor observations (W3C)
- **SWEET**: NASA JPL meteorology ontology
- **ENVO**: Environment ontology
- **OM**: Units of measure

### Example Queries

```prolog
% Find all software modules
?- all_modules(M).

% Get procedures in a module
?- module_procedures(rs232_module, P).

% Trace dependencies
?- depends_on_transitive(main_control_module, Dep).

% Version lineage
?- version_lineage(freepascal_port, Lineage).
```

## Historical Context

### Timeline

| Year | Version | Key Features |
|------|---------|--------------|
| 1984 | GDEM 1.0 | Commodore BASIC, map editor ($200) |
| 1985 | RADARPAS 1.0 | Turbo Pascal, EGA graphics ($600) |
| 1987 | RADARPAS 2.0 | Save/Load features ($800) |
| 1988 | RADARPAS 2.1 | This code (January 14, 1988) |
| 1990 | E300RX | Extensions for Lawrenceburg TX |
| 1991 | E250Term | New terminal with ISR |
| 2024 | FreePascal | Modern preservation build |

### Original Hardware Requirements (1988)

- Intel 8088/8086/80286 processor
- 256KB RAM minimum, 640KB recommended
- EGA graphics adapter
- RS-232 serial port
- Hayes-compatible or Racal-Vadic modem
- MS-DOS 2.0+

### Author

D. G. Lane (age 15 at time of original development)

## Development Guidelines for AI Assistants

### DO

- Build and test using Docker for consistency
- Reference `knowledge_base.pl` for semantic understanding
- Use `radar.pas` for any compilation tests
- Consult `PROGRAM_SLICING.md` for control flow understanding
- Keep changes minimal and focused on preservation

### DON'T

- Modify the original `19880114 RADAR.PAS` file
- Add features that require unavailable hardware
- Break FreePascal compatibility
- Remove historical comments or structure
- Create new files unless absolutely necessary

### When Asked About This Code

1. Explain this is **historical preservation** software from 1988
2. The original code controlled real weather radar systems
3. Modern build is for **educational/demonstration** purposes only
4. Hardware features (EGA, RS-232) are stubbed out
5. The Prolog knowledge base provides semantic metadata

## Common Tasks

### Adding Documentation

Edit existing markdown files rather than creating new ones.

### Updating the Modern Port

1. Edit `radar.pas`
2. Run `./build.sh` to verify compilation
3. Update the date comment at the top of the file
4. Commit with clear message referencing the change

### Querying the Knowledge Base

```bash
# If SWI-Prolog is available
swipl -s knowledge_base.pl -g "all_modules(M), writeln(M), halt."
```

### Program Slicing Analysis

The `radar_control_v0.pas` demonstrates backward slicing from `SendCom` procedure. Use this as a reference for understanding the core control logic.

## License

- **Original Software**: Copyright (C) 1987 D. G. Lane
- **Commercial Rights**: Sold to Ellason Corporation with unlimited distribution
- **Preservation Work**: Educational purposes

---

*This file helps AI assistants understand the RADARPAS codebase for effective collaboration.*
