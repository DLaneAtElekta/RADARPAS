// =============================================================================
// RADARPAS — Single async function whose execution IS the state graph
// =============================================================================
// The C# async/await state machine is the direct analogue of DCG threading:
//
//   Prolog DCG:  rule --> step1, step2, step3.
//     desugars to: rule(S0,S3) :- step1(S0,S1), step2(S1,S2), step3(S2,S3).
//
//   C# async:    async Task<State> Rule(State s) {
//                    s = await Step1(s);
//                    s = await Step2(s);
//                    return await Step3(s);
//                }
//
// Each `await` is a state transition edge.  The variable `s` is the threaded
// state — reassigned at each await point, exactly as S0→S1→S2 in DCG.
// The compiler generates the state machine; we don't need a separate monad.
// =============================================================================

using System;
using System.Collections.Immutable;
using System.Threading.Tasks;

namespace Radarpas;

// ---------------------------------------------------------------------------
// I/O boundary — every await point in the graph touches this
// ---------------------------------------------------------------------------

public interface IRadarpasIO
{
    Task<KeyInput> ReadKey();
    Task RenderScreen(AppState state);
    Task<byte[]?> FetchPictureData(RadarParams rp);
    Task<bool> DialStation(Station station);
    Task HangUp();
    Task Delay(int ms);
    TimeRec Now();
}

// ---------------------------------------------------------------------------
// Commands & Keys
// ---------------------------------------------------------------------------

public enum Command
{
    ToggleMap1, ToggleMap2, ToggleRangeMarkers, ToggleHelp,
    NextPicture, PrevPicture, FirstPicture, LastPicture,
    DeletePicture, SavePicture, FetchPicture,
    SelectStation, CallStation, HangUp,
    ToggleAutoMode, Configure, Storage, Quit, NoOp
}

public enum KeyInput
{
    F1, F2, F3, F4, F5, F6, F7, F8,
    PageUp, PageDown, Home, End, Delete,
    CharS, CharF, CharC, CharH, CharG, CharR,
    Char1, Char2, CharPlus, CharMinus,
    Escape, Other
}

// ---------------------------------------------------------------------------
// The program — one async function per mode, state threaded via s = await ...
// ---------------------------------------------------------------------------

public static class RadarpasProgram
{
    // =======================================================================
    // Entry point — the top-level DCG phrase
    //   radarpas_main --> initialize, modem_loop.
    // =======================================================================

    public static async Task<AppState> Run(IRadarpasIO io)
    {
        var s = AppState.Initial;
        s = await Initialize(s, io);
        s = await ModemLoop(s, io);
        return s;
    }

    // =======================================================================
    // initialize//0
    // =======================================================================

    static async Task<AppState> Initialize(AppState s, IRadarpasIO io)
    {
        s = s with
        {
            Mode = Mode.Modem,
            Screen = s.Screen with { HelpVisible = true, Message = "RADARPAS v2.1 — Press any key" }
        };
        s = await Render(s, io);       // ← await = state edge
        _ = await io.ReadKey();         // ← await = state edge (wait for keypress)
        s = s with { Screen = s.Screen with { Message = null } };
        return s;
    }

    // =======================================================================
    // modem_loop//0 — each iteration: render → read_key → dispatch
    //   modem_loop -->
    //       render_screen, read_key(Key), key_to_command(Key, Cmd),
    //       ( {Cmd = quit} -> [] ;
    //         apply_modem_command(Cmd), modem_loop ).
    // =======================================================================

    static async Task<AppState> ModemLoop(AppState s, IRadarpasIO io)
    {
        while (true)
        {
            s = await Render(s, io);                // ← state edge
            var key = await io.ReadKey();            // ← state edge
            var cmd = KeyToCommand(key);

            if (cmd == Command.Quit) return s;

            // Commands that cause mode transitions
            switch (cmd)
            {
                case Command.CallStation:
                    s = await DoCallStation(s, io);  // ← state edge
                    if (s.Connected)
                    {
                        s = s with { Mode = Mode.Interactive };
                        s = await InteractiveLoop(s, io);  // ← state edge (nested graph)
                        s = s with { Mode = Mode.Modem };
                    }
                    break;

                case Command.Storage:
                    s = await StorageMenu(s, io);    // ← state edge
                    break;

                case Command.NextPicture:
                case Command.PrevPicture:
                    s = ApplyPure(cmd, s);
                    s = await FetchAndDisplayPic(s, io); // ← state edge
                    break;

                default:
                    s = ApplyPure(cmd, s);
                    break;
            }
        }
    }

    // =======================================================================
    // interactive_loop//0 — connected to radar, F-keys send commands
    //   interactive_loop -->
    //       render_screen, read_key(Key), key_to_command(Key, Cmd),
    //       ( {Cmd = quit} -> finalize_interactive ;
    //         execute_interactive_command(Cmd), interactive_loop ).
    // =======================================================================

    static async Task<AppState> InteractiveLoop(AppState s, IRadarpasIO io)
    {
        // Send initial status query — like InterLoop's SendCom('X',150)
        s = s with { Screen = s.Screen with { Message = "ON LINE" } };

        while (true)
        {
            s = await Render(s, io);                    // ← state edge
            var key = await io.ReadKey();                // ← state edge
            var cmd = KeyToCommand(key);

            if (cmd == Command.Quit)
            {
                // finalize_interactive --> hang_up, set_mode(modem).
                s = await DoHangUp(s, io);              // ← state edge
                return s with { Mode = Mode.Modem };
            }

            switch (cmd)
            {
                case Command.FetchPicture:
                    s = await RxPicLoop(s, io);          // ← state edge (nested graph)
                    break;

                case Command.ToggleAutoMode:
                    s = s with { AutoMode = !s.AutoMode };
                    if (s.AutoMode)
                        s = await AutoLoop(s, io, 15);   // ← state edge (nested graph)
                    break;

                case Command.HangUp:
                    s = await DoHangUp(s, io);           // ← state edge
                    return s with { Mode = Mode.Modem };

                default:
                    s = ApplyPure(cmd, s);
                    break;
            }
        }
    }

    // =======================================================================
    // rx_pic_loop//0 — receive a picture
    //   rx_pic_loop -->
    //       set_mode(rx_pic), set_message("Receiving picture"),
    //       fetch_picture_data,
    //       ( {success} -> save_picture, set_mode(interactive)
    //       ;             set_error("Failed"), set_mode(interactive) ).
    // =======================================================================

    static async Task<AppState> RxPicLoop(AppState s, IRadarpasIO io)
    {
        s = s with
        {
            Mode = Mode.RxPic,
            Screen = s.Screen with { Message = "Receiving picture" }
        };
        s = await Render(s, io);                        // ← state edge

        var data = await io.FetchPictureData(s.RadarParams); // ← state edge

        if (data is not null)
        {
            var pic = PicRec.Empty with
            {
                Tilt = s.RadarParams.Tilt,
                Range = s.RadarParams.Range,
                Gain = s.RadarParams.Gain,
                TimeOfPic = io.Now(),
                Data = ImmutableArray.Create(data),
                Size = (uint)data.Length,
                Flags = ImmutableHashSet.Create(PicFlag.NotSaved)
            };
            var (newPics, idx) = InsertChronological(s.Pics, pic);
            s = s with
            {
                Pics = newPics,
                CurrPic = idx,
                Screen = s.Screen with { Message = "Picture saved" }
            };
        }
        else
        {
            s = s with { LastError = "No picture data", Screen = s.Screen with { Message = "Receive failed" } };
        }

        s = s with { Mode = Mode.Interactive };
        return s;
    }

    // =======================================================================
    // auto_loop(+Interval)//0 — automatic periodic fetch
    //   auto_loop(I) -->
    //       state(S), { S.auto_mode = true, S.connected = true },
    //       check_and_fetch(I),
    //       render_screen,
    //       ( key_pressed -> read_key, handle ; delay(1000) ),
    //       auto_loop(I).
    //   auto_loop(_) --> [].
    // =======================================================================

    static async Task<AppState> AutoLoop(AppState s, IRadarpasIO io, int intervalMin)
    {
        var lastFetch = io.Now();

        while (s.AutoMode && s.Connected)
        {
            var now = io.Now();
            if (now.Minute - lastFetch.Minute >= intervalMin)
            {
                s = await RxPicLoop(s, io);             // ← state edge
                lastFetch = now;
            }

            s = await Render(s, io);                    // ← state edge
            await io.Delay(1000);                       // ← state edge
        }

        return s with { AutoMode = false };
    }

    // =======================================================================
    // storage//0 — picture selection menu
    //   storage --> render_menu, read_key(Key),
    //     ( {Key = escape} -> [] ;
    //       {Key = enter}  -> set_curr_pic(Sel), fetch_pic ;
    //       navigate(Key), storage ).
    // =======================================================================

    static async Task<AppState> StorageMenu(AppState s, IRadarpasIO io)
    {
        int sel = s.CurrPic ?? 0;

        while (true)
        {
            s = s with { Screen = s.Screen with { Message = $"STORAGE — pic {sel + 1}/{s.Pics.Count}" } };
            s = await Render(s, io);                    // ← state edge
            var key = await io.ReadKey();               // ← state edge

            switch (key)
            {
                case KeyInput.Escape:
                    return s with { Screen = s.Screen with { Message = null } };

                case KeyInput.CharPlus:
                    if (sel < s.Pics.Count - 1) sel++;
                    break;

                case KeyInput.CharMinus:
                    if (sel > 0) sel--;
                    break;

                case KeyInput.Delete:
                    if (sel >= 0 && sel < s.Pics.Count)
                    {
                        var rest = s.Pics.RemoveAt(sel);
                        sel = Math.Min(sel, rest.Count - 1);
                        s = s with { Pics = rest, CurrPic = rest.IsEmpty ? null : sel };
                    }
                    break;

                default: // Enter / select
                    s = s with { CurrPic = sel, Screen = s.Screen with { Message = null } };
                    s = await FetchAndDisplayPic(s, io); // ← state edge
                    return s;
            }
        }
    }

    // =======================================================================
    // Leaf state transitions — each is a single await edge
    // =======================================================================

    /// <summary>render_screen --> { io:render(S) }.</summary>
    static async Task<AppState> Render(AppState s, IRadarpasIO io)
    {
        await io.RenderScreen(s);       // ← state edge
        return s;
    }

    /// <summary>call_station --> { io:dial(Station) }, set_connected(Result).</summary>
    static async Task<AppState> DoCallStation(AppState s, IRadarpasIO io)
    {
        if (s.CurrentStation is null)
            return s with { LastError = "No station selected" };

        s = s with { Screen = s.Screen with { Message = "Calling..." } };
        s = await Render(s, io);                        // ← state edge

        bool ok = await io.DialStation(s.CurrentStation); // ← state edge

        return ok
            ? s with { Connected = true,  Screen = s.Screen with { Message = "Connected" } }
            : s with { Connected = false, LastError = "Call failed" };
    }

    /// <summary>hang_up --> { io:hangup }, set_connected(false).</summary>
    static async Task<AppState> DoHangUp(AppState s, IRadarpasIO io)
    {
        if (!s.Connected) return s;
        await io.HangUp();                              // ← state edge
        return s with { Connected = false, Screen = s.Screen with { Message = "Disconnected" } };
    }

    /// <summary>fetch_and_display_pic --> { load current pic, render }.</summary>
    static async Task<AppState> FetchAndDisplayPic(AppState s, IRadarpasIO io)
    {
        // Triggers a re-render with the current picture
        return await Render(s, io);                     // ← state edge
    }

    // =======================================================================
    // Pure state transforms — no await, no state edge
    // These correspond to DCG rules that are entirely { Goal } bodies.
    // =======================================================================

    /// <summary>apply_command(+Cmd, +S, -S1) :- ... (pure, no I/O).</summary>
    static AppState ApplyPure(Command cmd, AppState s) => cmd switch
    {
        Command.ToggleMap1 => s with
        {
            Screen = s.Screen with { MapOn = s.Screen.MapOn.SetItem(0, !s.Screen.MapOn[0]) }
        },
        Command.ToggleMap2 => s with
        {
            Screen = s.Screen with { MapOn = s.Screen.MapOn.SetItem(1, !s.Screen.MapOn[1]) }
        },
        Command.ToggleRangeMarkers => s with
        {
            Screen = s.Screen with { RangeMarkers = !s.Screen.RangeMarkers }
        },
        Command.ToggleHelp => s with
        {
            Screen = s.Screen with { HelpVisible = !s.Screen.HelpVisible }
        },
        Command.ToggleAutoMode => s with { AutoMode = !s.AutoMode },
        Command.NextPicture => NavPic(s, 1),
        Command.PrevPicture => NavPic(s, -1),
        Command.FirstPicture => s.Pics.IsEmpty ? s : s with { CurrPic = 0 },
        Command.LastPicture => s.Pics.IsEmpty ? s : s with { CurrPic = s.Pics.Count - 1 },
        _ => s
    };

    static AppState NavPic(AppState s, int delta)
    {
        if (s.Pics.IsEmpty) return s;
        int cur = s.CurrPic ?? (delta > 0 ? -1 : 0);
        int next = Math.Clamp(cur + delta, 0, s.Pics.Count - 1);
        return s with { CurrPic = next };
    }

    // =======================================================================
    // key_to_command/2 — fact table
    // =======================================================================

    static Command KeyToCommand(KeyInput key) => key switch
    {
        KeyInput.F1       => Command.ToggleHelp,
        KeyInput.F2       => Command.ToggleMap1,
        KeyInput.F3       => Command.ToggleMap2,
        KeyInput.F4       => Command.ToggleRangeMarkers,
        KeyInput.F5       => Command.Storage,
        KeyInput.F6       => Command.SelectStation,
        KeyInput.F7       => Command.ToggleAutoMode,
        KeyInput.F8       => Command.Configure,
        KeyInput.PageUp   => Command.PrevPicture,
        KeyInput.PageDown => Command.NextPicture,
        KeyInput.Home     => Command.FirstPicture,
        KeyInput.End      => Command.LastPicture,
        KeyInput.Delete   => Command.DeletePicture,
        KeyInput.CharS    => Command.SavePicture,
        KeyInput.CharF    => Command.FetchPicture,
        KeyInput.CharC    => Command.CallStation,
        KeyInput.CharH    => Command.HangUp,
        KeyInput.Char1    => Command.ToggleMap1,
        KeyInput.Char2    => Command.ToggleMap2,
        KeyInput.CharR    => Command.ToggleRangeMarkers,
        KeyInput.CharPlus => Command.NextPicture,
        KeyInput.CharMinus=> Command.PrevPicture,
        KeyInput.Escape   => Command.Quit,
        _                 => Command.NoOp
    };

    // =======================================================================
    // insert_chronological/4
    // =======================================================================

    static (ImmutableList<PicRec>, int) InsertChronological(
        ImmutableList<PicRec> pics, PicRec newPic)
    {
        for (int i = 0; i < pics.Count; i++)
        {
            if (pics[i].TimeOfPic.Minute < newPic.TimeOfPic.Minute)
                return (pics.Insert(i, newPic), i);
        }
        return (pics.Add(newPic), pics.Count);
    }
}

// ---------------------------------------------------------------------------
// Display formatting — pure helpers
// ---------------------------------------------------------------------------

public static class DisplayFormat
{
    static readonly string[] TiltLabels =
        { "-1", "-1/2", "0", "1/2", "1", "1 1/2", "2", "2 1/2", "3", "4", "5", "7" };

    static readonly int[] RangeNm = { 25, 50, 100, 200, 400 };

    public static string FormatTilt(byte t) => t < TiltLabels.Length ? TiltLabels[t] : $"{t}";
    public static string FormatRange(byte r) => r < RangeNm.Length ? $"{RangeNm[r]}" : $"{r}";
    public static string FormatGain(byte g) => g == 17 ? "PRE" : $"{g}";
    public static string FormatTime(TimeRec t) => t.Format();
}
