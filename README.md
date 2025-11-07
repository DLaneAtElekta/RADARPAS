# RADARPAS - Ellason E300 Radar Terminal

[![FreePascal Build](https://github.com/DLaneAtElekta/RADARPAS/actions/workflows/build.yml/badge.svg)](https://github.com/DLaneAtElekta/RADARPAS/actions/workflows/build.yml)

Original Pascal and MODULA-2 code for the E300/E250 radar terminal system (see http://ewradar.com/)

**Historical Software from 1988** - This is the original Turbo Pascal source code for a commercial PC-based radar terminal system, preserved and made buildable with modern FreePascal compiler.

## 📖 Table of Contents

- [About](#about)
- [Quick Start](#quick-start)
- [Features](#features)
- [System Requirements](#system-requirements)
- [Building](#building)
- [Historical Context](#historical-context)
- [Technical Architecture](#technical-architecture)
- [Project Evolution](#project-evolution)
- [Files](#files)
- [License](#license)

## 🎯 About

**RADARPAS** (Radar Terminal in Pascal) was commercial software developed in 1985-1988 for the Ellason E300/E250 weather radar systems. It provided a PC-based terminal interface for remote radar operation and real-time weather radar image display.

This repository contains:
- ✅ **Original 1988 Turbo Pascal source code** (`19880114 RADAR.PAS`)
- ✅ **FreePascal-compatible version** for modern compilation (`radar.pas`)
- ✅ **Docker build environment** for reproducible builds
- ✅ **Complete build toolchain** (Makefile, scripts, CI/CD)

### What Made This Special (1988)

- **Real-time radar data** reception over 2400 baud modem
- **EGA graphics** with custom rendering engine (640×350, 16 colors)
- **Direct hardware programming** (port I/O, interrupts, DMA)
- **Multiple radar stations** with persistent configuration
- **Map overlay system** with geographic data
- **Picture storage** and retrieval system
- Ran on **8088/8086 PC** with 640KB RAM, no hard drive required

## 🚀 Quick Start

### Using Docker (Recommended)

```bash
# Build everything
./build.sh

# Run the program
docker run --rm -it -v "$(pwd):/build" radarpas-fpc:latest ./radarpas
```

### Manual Build

```bash
# Build Docker image
docker build -t radarpas-fpc:latest .

# Compile
docker run --rm -v "$(pwd):/build" radarpas-fpc:latest make

# Run
docker run --rm -it -v "$(pwd):/build" radarpas-fpc:latest ./radarpas
```

### Using Make

```bash
# Inside container
docker run --rm -it -v "$(pwd):/build" radarpas-fpc:latest /bin/bash

# Then:
make        # Build
make run    # Build and run
make clean  # Clean artifacts
make info   # Show build information
make help   # Show all targets
```

See **[BUILD.md](BUILD.md)** for comprehensive build instructions and troubleshooting.

## ✨ Features

### Original System (1988)

- **Remote Radar Control**
  - Connect via Hayes-compatible or Racal-Vadic modems
  - Real-time parameter adjustment (tilt, range, gain)
  - Station selection and configuration

- **Graphics Display**
  - 640×350 EGA graphics (16 colors)
  - Real-time radar image rendering
  - Dual map overlay system
  - Range circle markers
  - Custom character rendering

- **Data Management**
  - Automatic picture storage with metadata
  - Browse and recall saved images
  - Station-specific map libraries
  - Time-stamped file naming

- **Hardware Integration**
  - RS-232 serial communication (2400 baud)
  - Custom interrupt handlers
  - Printer support (Epson MX80, HP ColorJet)
  - Screen dump capability

### FreePascal Build (2024)

- ✅ Compiles on modern Linux systems
- ✅ Preserves original code structure
- ✅ Docker containerized build
- ✅ GitHub Actions CI/CD
- ℹ️ Hardware features stubbed (demonstration only)

## 💻 System Requirements

### Original System (1988)

- IBM PC/XT/AT or compatible
- Intel 8088/8086/80286 processor (4.77 MHz+)
- 256KB RAM minimum, 640KB recommended
- EGA graphics adapter
- Serial port (COM1 or COM2)
- Hayes-compatible or Racal-Vadic modem
- DOS 2.0 or higher
- Optional: Epson MX80 or HP ColorJet printer

### Modern Build System

- Docker or FreePascal 3.2.0+
- Linux, macOS, or Windows (with Docker)
- No special hardware required

## 🔨 Building

### Prerequisites

- **Docker** (recommended)
- Or **FreePascal Compiler** (`fpc`) 3.2.0+
- **Make** (GNU Make)

### Build Commands

```bash
# Automated Docker build
./build.sh

# Manual steps
docker build -t radarpas-fpc:latest .
docker run --rm -v "$(pwd):/build" radarpas-fpc:latest make

# Native build (if FPC installed locally)
make
./radarpas
```

### Build Artifacts

- `radarpas` - Compiled executable
- `*.o`, `*.ppu` - Object files and units (cleaned by `make clean`)

### Continuous Integration

GitHub Actions automatically builds and tests on every push:
- ✅ FreePascal compilation on Ubuntu
- ✅ Docker container build verification
- ✅ Artifact generation

## 📚 Historical Context

### Timeline

**1984 - GDEM 1.0**
> Graphical Data Entry Manager (GDEM) 1.0 was a line-based digital map and geographic data entry tool. Input was coordinates manually entered from chart-derived measurements using protractor and acetate. Output was binary formatted maps using a third-party EEPROM reader.
>
> GDEM 1.0 was implemented as 300 lines of Commodore BASIC on eighth grade PET computers. DATA statements. GOSUBs. Development payment: $200.

**1985 - RADARPAS 1.0 (E300PC)**
> RADARPAS was the Turbo Pascal program that implemented the E300PC 1.0 product for hardware PC. It received data from the E300 radar system over a modem and displayed the current radar feed with graphics overlay.
>
> Implemented in Turbo Pascal with EGA graphics, Hayes/Racal-Vadic modem support. Used direct hardware access: port I/O, interrupts, custom graphics rendering.
>
> Development payment: $600 (gave Ellason rights to sell unlimited copies).

**1987 - RADARPAS 2.0**
> Enhanced with save and load options for pictures and improved station management.
>
> Upgrade payment: $800 per copy.

**1988 - Version 2.1** (This Code)
> Final revision dated January 14, 1988. Included bug fixes and refinements.

**1990s - Evolution**
- **E300RX extensions** (1990) - Lawrenceburg, TX deployment
- **E250Term** (1991) - New terminal for E250 systems with ISR
- **TopSpeed Modula-2** port - Rewritten in Modula-2
- Storm cell recognition algorithm development
- Greensville trip - Field testing

**Late 1990s - Advanced Features**
- Dynamic camera model (1997) and orthorectification
- ERDAS plugin architecture
- Nelder-Mead optimization
- Forstner-like operator and tie point extraction

### Development Context

This software was written when the author was 15 years old, representing state-of-the-art PC programming for its era:

- **No IDE** - Text editor and command-line compiler
- **No debugger** - Logic and hex dump debugging
- **No stack overflow** - Careful memory management by hand
- **No internet** - Documentation from books and manuals
- **Direct hardware** - Programming to the metal
- **Real-time constraints** - 2400 baud, no buffering, interrupt-driven

A complete professional application in ~1,900 lines of Pascal.

## 🏗️ Technical Architecture

### Modular Design

```
RADARPAS
├── Miscellaneous Routines (DOS interface)
├── Graphics Routines (EGA rendering)
├── Screen Format Routines (UI layout)
├── RS232 Routines (modem/serial)
├── Storage (file management)
├── Initialization/Configuration
└── Main Loops (Modem/Interactive/Receive)
```

### Key Technologies

**Graphics Engine**
- Custom EGA plane manipulation
- Bit-blit operations for speed
- Run-length encoded image format
- Dual-buffer map overlay system
- Trigonometric lookup tables (ASin/ACos)

**Communication**
- Interrupt-driven RS-232 (IRQ 3/4)
- Custom serial protocol with checksums
- Real-time data streaming
- Flow control and error recovery

**Data Structures**
- Circular buffer for serial input (256 bytes)
- Picture metadata records (time, tilt, range, gain)
- Compressed line format for radar data
- Map overlay coordinate system

**Hardware Access**
- Direct port I/O (`port[$3C4]`, etc.)
- Inline assembly for interrupts
- Video memory access (`Mem[$A000:offset]`)
- BIOS and DOS interrupts

### FreePascal Adaptations

The modern `radar.pas` version:
- Uses `{$MODE TP}` for Turbo Pascal compatibility
- Replaces inline assembly with FreePascal syntax
- Stubs hardware access for demonstration
- Uses `Dos` unit for compatible types
- Maintains original algorithm structure

## 🗂️ Files

### Source Code
- **`19880114 RADAR.PAS`** - Original Turbo Pascal source (1988)
- **`radar.pas`** - FreePascal-compatible version

### Build System
- **`Dockerfile`** - Container build environment
- **`Makefile`** - Build automation
- **`build.sh`** - One-command build script
- **`.dockerignore`** - Docker optimization

### Documentation
- **`README.md`** - This file
- **`BUILD.md`** - Detailed build instructions

### CI/CD
- **`.github/workflows/build.yml`** - GitHub Actions workflow

### Historical
- **`documents/`** - Original documentation and notes

## 🔬 Project Evolution

This codebase represents the foundation for a multi-decade evolution:

```
1984: GDEM 1.0 (Commodore BASIC)
  ↓
1985: RADARPAS 1.0 (Turbo Pascal)
  ↓
1987: RADARPAS 2.0 (Save/Load features)
  ↓
1988: RADARPAS 2.1 (This code)
  ↓
1990: E300RX extensions
  ↓
1991: E250Term + ISR
  ↓
199?: TopSpeed Modula-2 port
  ↓
1997: Dynamic camera model, orthorectification
  ↓
199?: ERDAS plugin architecture
  ↓
2024: FreePascal preservation build
```

### Related Technologies Developed
- Storm cell recognition algorithms
- Nelder-Mead optimization implementations
- Forstner-like operator for tie point extraction
- Geographic orthorectification systems

## 📜 License

**Original Software:**
Copyright (C) 1987 D. G. Lane. All rights reserved.

**Build System and FreePascal Port:**
Provided for historical preservation and educational purposes.

This code represents commercial software that was sold to Ellason Corporation with rights to unlimited distribution. The preservation and adaptation work makes this historical codebase accessible to modern systems.

## 🙏 Acknowledgments

- **Arnold Ellason** - Ellason Corporation, original client and radar system developer
- **Turbo Pascal** - Borland's revolutionary compiler that made this possible
- **FreePascal Team** - Keeping Pascal alive and providing excellent Turbo Pascal compatibility
- **EWR Radar** - Weather radar systems (http://ewradar.com/)

---

*"This is some very old code written when I was 15 years old. I still have a version that runs on a DOS simulator (though it only shows canned data)."* - Original README

**Historical software preservation project - 2024**
