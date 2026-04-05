// =============================================================================
// RADARPAS Core Types — Immutable records for the state graph
// =============================================================================
// The async/await state machine pattern:
//
//   async Task<AppState> SomeMode(AppState s, IRadarpasIO io) {
//       s = await Step1(s, io);    // state edge — S0 → S1
//       s = await Step2(s, io);    // state edge — S1 → S2
//       return s;                  // final state
//   }
//
// Each function is a node in the state graph.  Each `await` is an edge.
// The `s` variable is the threaded state, reassigned at each transition —
// exactly as DCG desugars  rule --> a, b.  into  rule(S0,S2) :- a(S0,S1), b(S1,S2).
//
// All records are immutable.  "Mutation" uses C# with-expressions which
// allocate a new record — the same semantics as Prolog unification producing
// a new state term.
// =============================================================================

using System;
using System.Collections.Immutable;

namespace Radarpas;

// ---------------------------------------------------------------------------
// time_rec(Day, Minute, Millisec)
// ---------------------------------------------------------------------------

/// <summary>Packed time, matching the original Pascal TimeRec</summary>
public sealed record TimeRec(ushort Day, ushort Minute, ushort Millisec)
{
    public static readonly TimeRec Zero = new(0, 0, 0);

    public int Hour => Minute / 60;
    public int Min  => Minute % 60;
    public int Sec  => Millisec / 1000;

    public string Format() => $"{Hour:D2}:{Min:D2}";
}

// ---------------------------------------------------------------------------
// Operating mode atoms
// ---------------------------------------------------------------------------

public enum Mode { Modem, Interactive, WaitPic, RxPic, RxGraph }

// ---------------------------------------------------------------------------
// radar_params(Tilt, Range, Gain, Time)
// ---------------------------------------------------------------------------

public sealed record RadarParams(
    byte Tilt,      // 0..11
    byte Range,     // 0..4
    byte Gain,      // 1..17
    TimeRec Time)
{
    public static readonly RadarParams Default = new(2, 2, 9, TimeRec.Zero);
}

// ---------------------------------------------------------------------------
// pic_rec/8
// ---------------------------------------------------------------------------

public enum PicFlag { NotSaved, BeingDownloaded }

public sealed record PicRec(
    byte Tilt,
    byte Range,
    byte Gain,
    TimeRec TimeOfPic,
    uint Purge,
    ImmutableHashSet<PicFlag> Flags,
    uint Size,
    ImmutableArray<byte>? Data)
{
    public static readonly PicRec Empty = new(
        0, 0, 1, TimeRec.Zero, 0,
        ImmutableHashSet<PicFlag>.Empty, 0, null);
}

// ---------------------------------------------------------------------------
// screen_state/5
// ---------------------------------------------------------------------------

public sealed record ScreenState(
    ImmutableArray<bool> MapOn,
    bool RangeMarkers,
    int HelpMode,
    bool HelpVisible,
    string? Message)
{
    public static readonly ScreenState Initial = new(
        ImmutableArray.Create(false, false),
        true, 0, false, null);
}

// ---------------------------------------------------------------------------
// station/3
// ---------------------------------------------------------------------------

public sealed record Station(
    string Name,
    string Phone,
    ImmutableList<PicRec> Pictures);

// ---------------------------------------------------------------------------
// app_state/9 — the single state term threaded through the entire program
// ---------------------------------------------------------------------------

/// <summary>
/// The complete application state.  Every async function in RadarpasProgram
/// takes this as input and returns a (possibly modified) copy as output.
///
/// Prolog equivalent:
///   app_state(Mode, Station, Pics, CurrPic, RadarParams, Screen,
///             Connected, AutoMode, LastError)
/// </summary>
public sealed record AppState(
    Mode Mode,
    Station? CurrentStation,
    ImmutableList<PicRec> Pics,
    int? CurrPic,
    RadarParams RadarParams,
    ScreenState Screen,
    bool Connected,
    bool AutoMode,
    string? LastError)
{
    public static readonly AppState Initial = new(
        Mode.Modem,
        null,
        ImmutableList<PicRec>.Empty,
        null,
        RadarParams.Default,
        ScreenState.Initial,
        false,
        false,
        null);
}
