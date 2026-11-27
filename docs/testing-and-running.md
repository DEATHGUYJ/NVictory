# Testing and running a game (NVictory)

For this fork on its target PC: Windows 10/11 x64, RTX 3080 12 GB, Ryzen 5 5600T,
32 GB RAM. The fork is NVIDIA-only. It has **not been run on that PC yet**, so
this guide is also the plan for the first run. Read [README.md](../README.md) first.

You need your own copy of the title, already on your disk. This repository has
no game files and this guide does not cover how to get them.

## 1. Before you start

| Check | How |
|---|---|
| Driver | Current NVIDIA driver (Game Ready or Studio). Note the version: you will report it. |
| CPU | AVX2 (the 5600T has it). |
| Page file | 32-48 GB or more, on the NVMe drive. System Properties, Advanced, Performance, Virtual memory. Without it a run can end in an out-of-memory error. |
| Tools | Rust (the toolchain is pinned by `rust-toolchain.toml`), MSVC build tools, Git. |
| Free RAM | Close the browser and other programs. Run from a normal window, not as administrator. |
| Config | `copy victory.example.toml victory.toml`, then set `game_dir` to a folder **outside** this repository. |

## 2. Build (or download a ready build)

**Without building.** Every push to `a-publier` builds both versions on GitHub. Open the repository's
**Actions** tab, pick the newest **Build** run, and download `NVictory-<commit>` under **Artifacts**
(you must be signed in; kept 30 days). Unzip it **outside** the game folder. It has the same layout
as the repository (`target\diag\victory.exe`, `target\release\victory.exe`, `scripts`, the docs),
so every command below works from the unzipped folder. Then, once, in PowerShell in that folder:

```powershell
Get-ChildItem -Recurse | Unblock-File     # Windows marks downloaded scripts as blocked
```

You do not need Rust or the MSVC tools for this; you still need them for section 3.

**Building it yourself.**

Two builds exist. Use `diag` for everything in this guide: it has the counters
and log lines the notes ask for. Use `release` only when you want the fastest
build and do not need them.

```powershell
cargo build --locked --profile diag -p victory --features diagnostics   # target\diag\victory.exe
cargo build --locked --release -p victory                               # target\release\victory.exe
```

## 3. Test the code (no game needed)

Run these first. A failure here is a build problem, not a game problem.

```powershell
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
cargo test --workspace --locked
cargo test --workspace --all-features --locked -- --test-threads=1     # what CI runs
```

Tests that need a real card are marked `#[ignore]` and are not part of the lines
above. Run them on the 3080, one area at a time, and keep the output:

```powershell
cargo test -p victory-gpu --release -- --ignored --nocapture
cargo test -p victory-gpu --release -- --ignored levels_on_demand --nocapture
```

Notes:
- A few ignored tests write to the Windows event log or take minutes. Read the
  doc comment above a test before running it by name.
- `cargo test` for `victory-gpu` on Linux does not work: the crate is Windows-only.
  From Linux you can only type-check: `cargo clippy --workspace --all-targets --locked --target x86_64-pc-windows-gnu -- -D warnings`.
- Anything not run on the 3080 is untested, whatever the type-check says.

## 4. Prepare the game's shaders (once per driver and build)

The first run of a new build stutters while the driver makes pipelines. Do the
translation and warm-up ahead of time:

```powershell
target\diag\victory.exe shaders <the shader archives of your copy>   # every shader translated, minutes
target\diag\victory.exe warm --used                                   # pipelines for this driver and build
```

Redo `warm` after a driver update or a rebuild that changes the translator.
Changing the translator invalidates the shader cache, so expect the first run
after such a change to be slow.

## 5. Run

```powershell
scripts\play.ps1 -Exe <path of your copy's executable>
```

The first run opens the settings window (executable, console profile, output
size, frame rate, ray tracing, memory use, build, and the safe-mode, in-place
and wide-indirect boxes). Choices are saved in `%LOCALAPPDATA%\victory\launcher.json`.
`-Settings` opens it again; `-NoDialog` never shows it.

**Run order for the first sessions.** Change one thing at a time.

| Step | Command | What you learn |
|---|---|---|
| 1 | `scripts\play.ps1 -Exe <exe> -Safe` | Does it boot at all, without the newer fast paths? |
| 2 | `scripts\play.ps1 -Exe <exe>` | The default NVIDIA settings. Does it still boot? What is a frame? |
| 3 | add `-More @{VICTORY_PANEL='1'}` | Numbers on the picture: frame cost and where it goes. |
| 4 | `-InPlaceProbe`, then `-InPlace` only if the probe passes | Whether this driver can use title memory in place (see README). |
| 5 | `-WideIndirect` only if tiles are missing at the bottom of the frame | Untested on NVIDIA; can lose the device. |
| 5b | `-Async` | Faster submission. Check faces and skin, and that videos do not repeat frames. |
| 6 | `-RayTracing` last | About a third slower; leave off at first. |

For less memory use, choose "Series S" or the **32 GB PC preset** in the settings
window, or `-More @{VICTORY_OUTPUT='1920x1080'}`.

## 6. What to collect

Logs go to **stderr**. Capture them to a file:

```powershell
scripts\play.ps1 -Exe <exe> -NoDialog 2>&1 | Tee-Object run1.log
```

`VICTORY_LOG=debug` (diag builds only) shows more; start without it.

For each run, note:

1. Driver version, Windows build, and which launcher switches you used.
2. Whether it booted, reached the menu, and reached the world.
3. The line starting **"recording and mapping waits per frame"** and the **frame
   account** line (both in a `diag` build, printed every batch of frames).
4. The line "errors the graphics driver reported to the system since the start",
   if it appears. It means NVIDIA's driver logged an error (event 153) and the
   risky indirect-window path was switched off for the rest of the run.
5. Peak RAM and VRAM (Task Manager, or `VICTORY_MEMORY_MAP=1` for where RAM goes).
6. Any crash message, device-lost line, or missing/black parts of the picture.

If the waits in line 3 are under about 1 ms a frame, DexNom's parallel recording
and per-range lock would not help this PC.

### A single frame, and a timed period of play

These are two different things; use both.

**One frame (a capture you can replay).** Use the recorder (section 8). It writes down one
frame's GPU work and lets you rerun it without the game. Pick a heavy frame: stand in
the scene first, then trigger it by time (`VICTORY_RECORD_AT='120'` is 120 seconds after the
device was made, or `'f5000'` for the 5,000th present) or by creating the file `go` in the
capture folder. Read `notes.txt` in the capture folder. This is for finding where the card's
time goes. It is not a frame-rate test.

**A timed period (a log of real play).** Play for a fixed time in a fixed place and keep the log.
Start with 5 minutes, then 30 minutes for stability. The same place and the same route each
time makes runs comparable.

```powershell
# Start the log, note the time, play, then quit the game from its own menu if you can.
scripts\play.ps1 -Exe <exe> -NoDialog 2>&1 | Tee-Object run-5min.log
```

- Quit from the game's menu where possible. The end-of-run summary lines (the counters and the
  driver-error count) are printed on a clean exit and are lost if you kill the process.
- If you must stop it, close the window, and say the log has no summary.
- Write down the wall-clock start and end times, what you did, and when anything looked wrong
  (stutter, black faces, a hitch), so the log lines around that time can be found.
- The frame account and "recording and mapping waits per frame" lines repeat every batch of
  frames, so a long run gives many samples. Send the whole file, not only the last lines.
- Warm the pipelines first (`victory warm --used`), or the first minutes measure the driver
  compiling.

**Automatic 5-minute run.** `scripts\test-run.ps1` starts the game, lets it run for a set time, asks it
to close (so the end-of-run summary prints), stops it after 30 seconds if it does not, saves the log to
`%LOCALAPPDATA%\victory\logs\test-<date>.err.log`, and prints the lines to send back.

```powershell
scripts\test-run.ps1 -Exe <path of your copy's executable>              # 5 minutes
scripts\test-run.ps1 -Minutes 30                                        # soak (uses the saved executable)
scripts\test-run.ps1 -Safe -More @{VICTORY_PANEL='1'}                   # same switches as play.ps1
```

It has not been run on Windows yet. If the log is empty, run `play.ps1` by hand.

| Run | Length | Purpose |
|---|---|---|
| Boot | until the menu | Does it start; adapter and driver lines. |
| Short | 5 minutes in one scene | Frame cost, the two log lines above, first stutter. |
| Soak | 30 minutes | Leaks (RAM, VRAM), device loss, long-run stutter. |
| Capture | one frame | Where a slow frame spends its time. |

## 7. Troubleshooting

| Symptom | Try |
|---|---|
| Out of memory | Check the page file. Settings: memory "low". `-More @{VICTORY_WINDOW_BUDGET_MB='2048'}`. Close other programs. |
| Device lost / driver reset | `-Safe`. Leave `-InPlace`, `-WideIndirect` and `-RayTracing` off. Keep the log lines before the loss; the driver's own event-log entry is recorded in the log. |
| Missing tiles at the bottom of the frame | `-WideIndirect` (untested; see README). |
| Stutter for minutes on a new build | Run `victory warm --used`; the first run after a driver or build change builds pipelines. |
| Wrong GPU used | The launcher asks for the NVIDIA adapter. On a PC with an iGPU, check the log's adapter line. |
| Slow world frames | Frame time is limited by the one submit thread. Use `VICTORY_PANEL=1` and send the frame account line. |
| Faces or skin missing, or a video repeats frames | Run without `-Async` (the default). These faults are known with `VICTORY_THIN` and `VICTORY_JOIN_PARTS` on NVIDIA. |
| Slow but the picture is right | Try `-Async` and check faces and videos again. |
| Launcher warns "no NVIDIA adapter" | The fork is NVIDIA-only. Check the driver and Device Manager. |

### Reducing RAM use

The title wants more than 32 GB with the defaults (`docs/findings.md`: command-list allocators about
9 GB, title-window copies about 7 GB, uploads about 4 GB). None of the figures below is measured on
this PC. Change one thing per run and compare the peak in Task Manager.

1. **Find out where it goes.** Run once with `-More @{VICTORY_MEMORY_MAP='1'}` and keep the log.
2. **Cap the window copies.** `-More @{VICTORY_WINDOW_BUDGET_MB='2048'}` (the launcher uses 4096). The
   memory setting "low" in the settings window does this.
3. **Smaller picture, lighter profile.** Series S, or `-More @{VICTORY_OUTPUT='1920x1080'}`.
4. **Free finished lists sooner.** `VICTORY_BURY_LAG=8` and `VICTORY_KEEP_SNAPSHOTS_MB=128`. The lag
   exists because of device losses from memory freed too early, so test this one on its own.
5. **Use title memory in place.** `-InPlaceProbe` first, then `-InPlace`. It removes host copies
   instead of capping them, and is the largest potential saving. Leave it off if the probe fails.
6. **Keep the page file** at 32-48 GB or more. It does not lower use; it turns a crash into a slowdown.

Ideas that need code changes (not done): pool command-list allocators per frame slot, reuse a fixed
ring of upload staging buffers, and drop host copies of texture levels that the card already holds.
Send the `VICTORY_MEMORY_MAP` output before any of these, so the top items are the real ones.

## 8. Recording one frame and replaying it

To investigate one slow frame without the game, record it in a `diag` build and
replay it in seconds. See [replay.md](replay.md).

```powershell
scripts\play.ps1 -Exe <exe> -More @{VICTORY_RECORD='D:\victory-data\rec'; VICTORY_RECORD_AT='120'}
target\diag\victory.exe replay D:\victory-data\rec --loops 5 --timing detailed
```

A capture can be about 9 GB and stops the title while it is written; keep it
outside the repository and delete it afterwards.

## 9. Reporting

When something fails, send: the run log, the lines named in section 6, the
launcher switches, and the driver version. Say what you had already ruled out.
Do not paste game files or keys.
