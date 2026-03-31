# Pascal to Elixir Translation Strategy

This document outlines the strategy for translating RADARPAS from the original
1988 Turbo Pascal source (RADAR.PAS, 1,894 lines) to idiomatic Elixir.

---

## 1. Source Material

The translation is from the original **Turbo Pascal 3.0** source file
`19880114 RADAR.PAS`, dated January 14, 1988. This is a single monolithic
file containing all types, constants, and procedures for a complete PC-based
weather radar terminal system.

---

## 2. Core Translation Principles

### 2.1 Global Mutable State → GenServer State

The Pascal program used ~50 global variables for all state. In Elixir:

| Pascal | Elixir |
|--------|--------|
| `var Mode: ModeType` | `%Radar{mode: :modem}` in GenServer state |
| `var Pic: array[0..100] of PicRec` | `pics: []` list in state |
| `var CurrPic, MaxPic: integer` | `curr_pic: 0, max_pic: 0` in state |
| `var HelpOn, Gfx1On: boolean` | `%Screen{help_on: true, gfx1_on: false}` |
| `var CurrPlane: PlaneSet` | `%Graphics{curr_plane: MapSet.new([0,1,2,3])}` |

### 2.2 Hardware Interrupts → Message Passing

The original RS232 handler was a hardware ISR (Interrupt Service Routine)
hooked into IRQ4 via `INT 21h, AH=$25`. It used inline x86 assembly for
register save/restore and IRET.

| Pascal | Elixir |
|--------|--------|
| `procedure RS232Interupt` (ISR) | `handle_info({:circuits_uart, ...})` |
| `Port[ComPort]:=ord(Charac)` | `Circuits.UART.write(pid, <<char>>)` |
| `data:=port[ComPort]` | Pattern match on UART message |
| Circular buffer `Buf[BufBeg..BufEnd]` | Binary accumulator in GenServer state |
| `inline($FA)` (CLI) / `inline($FB)` (STI) | Serialized via GenServer |

### 2.3 Direct EGA Memory → Abstract Draw Commands

The original wrote directly to EGA video memory at segment `$A000`,
using plane selection (ports `$3C4/$3C5`) and function selection
(ports `$3CE/$3CF`).

| Pascal | Elixir |
|--------|--------|
| `Mem[$A000:offset]:=value` | `{:set_pixel, x, y}` command |
| `SelectPlane([0,1])` | `{:set_planes, MapSet.new([0,1])}` |
| `SelectFunc(_Clr)` | `{:set_func, :clear}` |
| `GRPlot(X,Y)` | `Graphics.plot(x, y)` |
| `GRLine(X1,Y1,X2,Y2)` | `Graphics.line(x1, y1, x2, y2)` |

### 2.4 DOS System Calls → Elixir Standard Library

| Pascal | Elixir |
|--------|--------|
| `MsDos(Registers)` with AH=$4E (FindFirst) | `File.ls(dir)` |
| `MsDos(Registers)` with AH=$4F (FindNext) | Enum iteration |
| `MsDos(Registers)` with AH=$2C (GetTime) | `DateTime.utc_now()` |
| `ChDir(StationName)` | `Path.join(base_dir, name)` |
| `Assign(PicFile,...); ReSet(PicFile,1)` | `File.read(path)` |
| `BlockRead(...)` / `BlockWrite(...)` | `File.read/write` |
| `MkDir(...)` / `RmDir(...)` | `File.mkdir/rm_rf` |

---

## 3. Module Mapping

The original single-file program is split into modules following its
natural section boundaries (marked by comment headers in the source):

| Pascal Section | Lines | Elixir Module |
|---------------|-------|---------------|
| Type definitions & constants | 17-104 | `Radarpas.CoreTypes` |
| Miscellaneous Routines | 108-173 | (absorbed into other modules) |
| Graphics Routines | 178-508 | `Radarpas.Graphics` |
| Screen Format Routines | 514-825 | `Radarpas.Screen` |
| RS232 Routines | 828-1073 | `Radarpas.Communication` |
| Storage (FetchPic, SavePic) | 1076-1109, 1127-1146 | `Radarpas.Pictures` |
| Storage (LoadStation, SelectStation) | 1204-1393 | `Radarpas.Stations` |
| Screen Dump | 1396-1484 | `Radarpas.ScreenDump` |
| Init, Config, Main loops | 1488-1886 | `Radarpas.Radar` |
| Application entry point | 1867-1886 | `Radarpas.Application` |

---

## 4. Type Translation Rules

| Pascal Type | Elixir Translation |
|-------------|-------------------|
| `0..11` (subrange) | `integer()` with guard clauses |
| `string[N]` | `String.t()` (binary) |
| `array[a..b] of byte` | List or binary |
| `record ... end` | `defstruct` |
| `(A,B,C)` enumeration | Atoms `:a`, `:b`, `:c` |
| `set of 0..3` | `MapSet.t()` |
| `^Type` (pointer) | Value or `nil` |
| `byte` | `non_neg_integer()` (0..255) |
| `integer` | `integer()` |
| `boolean` | `boolean()` |
| `char` | Integer (codepoint) or binary |
| `file` / `text` | File handles via `File` module |

---

## 5. Procedure Translation Patterns

### 5.1 Pure Functions (No side effects)

```pascal
procedure GRPlot(X,Y: integer);
  ...
  Mem[$A000:AtByte]:=$FF;
end;
```

→ Returns a draw command instead of mutating video memory:

```elixir
def plot(x, y) do
  {:set_pixel, x, y}
end
```

### 5.2 State-Mutating Procedures → Return Updated State

```pascal
procedure WriteHelp;
begin
  HelpOn := not HelpOn;
  ...
end;
```

→

```elixir
def toggle_help(state) do
  %{state | help_on: not state.help_on}
end
```

### 5.3 I/O Procedures → GenServer Calls

```pascal
procedure Tx(Charac: char);
begin
  repeat until (port[ComPort+5] and $20)=$20;
  Port[ComPort]:=ord(Charac);
end;
```

→

```elixir
def tx(char) do
  GenServer.call(__MODULE__, {:tx, char})
end
```

### 5.4 Interrupt Handlers → GenServer handle_info

```pascal
procedure RS232Interupt;
begin
  inline($1E/$50/...); {PUSH registers}
  data:=port[ComPort];
  case Mode of
    Modem: ...
    Interactive: ...
  end;
  inline($07/$5E/...); {POP registers}
  inline($CF); {IRET}
end;
```

→

```elixir
def handle_info({:circuits_uart, _port, data}, state) do
  new_state = Enum.reduce(:binary.bin_to_list(data), state, &process_byte/2)
  {:noreply, new_state}
end
```

---

## 6. Key Algorithm Translations

### 6.1 Radar Response Parsing (SetParams)

The 10-byte Q-response from the E300 radar used bit-packing:
- Byte 2: Gain in upper nibble
- Byte 3: Tilt (inverted from 12) in lower nibble, RT flags in upper
- Byte 4: Range encoded in bits 3-5

Translated using Elixir binary pattern matching and Bitwise operations.

### 6.2 Picture Compression (DispLine)

Run-length encoded scan lines with 2-byte entries:
- Bits 15-13: color (0=off, 1=red, 2=green, 3=yellow)
- Bits 10-0: pixel count
- Terminated by `$18` byte

Translated using recursive binary pattern matching.

### 6.3 Map Coordinate Conversion (WriteGfx)

Polar-to-screen coordinate conversion using precomputed ASin/ACos
lookup tables (361 entries each), avoiding any floating-point
trigonometry on the 8088 processor.

Translated as module attributes with Enum.at lookups.

### 6.4 Range Marker Circles (WriteRngMks)

Five concentric circles drawn using precomputed Y-to-X lookup tables
(Circle1..Circle5), exploiting 4-fold symmetry around center (320, 175).

Translated as list comprehensions over the lookup table module attributes.

---

## 7. Supervision Tree

```
Radarpas.Supervisor
├── Radarpas.Communication (GenServer)
│   └── Manages UART port, receives serial data,
│       dispatches based on mode (replaces RS232Interupt)
└── Radarpas.Radar (GenServer)
    └── Manages application state, processes commands,
        coordinates display (replaces main loops)
```

---

## 8. What Changed

| Aspect | Pascal Original | Elixir Translation |
|--------|----------------|-------------------|
| Architecture | Single-threaded, interrupt-driven | Multi-process, message-passing |
| State | ~50 global variables | Immutable structs in GenServers |
| Concurrency | Hardware IRQ + CLI/STI | OTP supervision + GenServer |
| Graphics | Direct EGA memory writes | Abstract command lists |
| Serial I/O | Port I/O + ISR | Circuits.UART + active mode |
| File I/O | DOS INT 21h | Elixir File module |
| Error handling | IOResult + goto | {:ok, _} / {:error, _} tuples |
| Memory mgmt | Fixed arrays, pointer arithmetic | Dynamic lists, garbage collection |

---

## 9. What Was Preserved

- **All lookup tables**: Circle1-5, ASin, ACos, TiltVal, RangeVal, Colors
- **Protocol parsing**: SetParams byte-level parsing of Q-response
- **Picture format**: DispLine run-length decoding algorithm
- **Map rendering**: WriteGfx polar-to-cartesian conversion
- **Command structure**: Same keyboard-to-command mapping
- **Mode state machine**: Modem → Interactive → WaitPic → RxPic → RxGraph
- **File naming convention**: HHMM<tilt><range><gain>.PIC
