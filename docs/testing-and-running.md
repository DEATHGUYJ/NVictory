# Testing and running a game (NVictory, `combined` branch)

For the target PC: Windows 10/11 x64, RTX 3080 12 GB, Ryzen 5 5600T, 32 GB RAM. This branch is
trustno1-coder/VIctory-NVIDIA (on foxhound) with NVictory's additions. It has **not been run on that
PC yet**.

You need your own copy of the title, already on your disk. This repository has no game files and
this guide does not cover how to get them.

## 1. Before you start

| Check | How |
|---|---|
| Driver | A current NVIDIA driver. Note the version: you will report it. |
| Page file | 32-48 GB or more, on the SSD (System Properties, Advanced, Performance, Virtual memory). With 32 GB of RAM this is what turns an out-of-memory crash into a slowdown. |
| HAGS | Hardware-accelerated GPU scheduling on (Settings, Display, Graphics). Frame generation needs it. |
| Free RAM | Close the browser and other programs. Run from a normal window, not as administrator. |

## 2. Get the program

**Ready build (no Rust needed).** On GitHub: the **Actions** tab, the newest **Build** run on
`combined`, **Artifacts**. Unzip it outside the game folder, then in PowerShell in that folder:

```powershell
Get-ChildItem -Recurse | Unblock-File       # Windows blocks downloaded scripts otherwise
.\Get-NVIDIA-DLSS.cmd                        # once: NVIDIA's DLSS files (about 70 MB), from NVIDIA
```

**Building it yourself.** Rust and the Visual Studio Build Tools ("Desktop development with C++"),
then `git clone -b combined https://github.com/DEATHGUYJ/NVictory`, `cd NVictory`,
`.\Get-NVIDIA-DLSS.cmd`. The launcher builds the layer the first time.

**Frame generation on the 3080** is AMD's FSR 3 (2x). It needs AMD's FidelityFX DLLs
(`amd_fidelityfx_loader_dx12.dll`, `amd_fidelityfx_framegeneration_dx12.dll`) in a `fidelityfx`
folder next to `victory.exe`, or `VICTORY_FIDELITYFX_DIR`. Without them the game runs without frame
generation.

## 3. Run

```powershell
powershell -ExecutionPolicy Bypass -File scripts\play-foxhound.ps1 -Exe 'D:\MyCopy\game_scarlett_master.exe'
```

- **F1** in the game: settings menu (DLSS, frame generation, frame rate cap, console profile, picture
  size). "SAVE AND RESTART NOW" applies them.
- **F3**: stats panel (frame rate, frame time, draws, GPU and CPU busy, RAM and VRAM).
- Logs: `%LOCALAPPDATA%\victory\logs\victory-nvidia-<date>.log`, written by the launcher every run.

**Order for the first sessions.** Change one thing at a time.

| Step | Options | What you learn |
|---|---|---|
| 1 | `-SeriesS -Dlss quality` | Boots? Lightest profile. |
| 2 | (defaults: Series X, 2560x1440, DLSS Quality) | The real target. Frame rate in the F3 panel. |
| 3 | `-Preload` once | Every shader made first: fewer stutters afterwards. |
| 4 | F1: frame generation on (FSR 3) | Needs the FidelityFX DLLs. Watch VRAM in F3. |
| 5 | `-More @{VICTORY_JOIN_PARTS='8'}` | Whether 8 join parts beat the 4 NVictory picks on 12 threads. |

## 4. A single frame, and a timed period of play

**Timed play.** `scripts\test-run.ps1` runs the launcher for a set time, asks the game to close (so
the end-of-run lines print), stops it after 30 seconds if it does not, and prints the lines to send.

```powershell
scripts\test-run.ps1 -Exe 'D:\MyCopy\game_scarlett_master.exe'                   # 5 minutes
scripts\test-run.ps1 -Exe ... -Minutes 30                                         # soak
scripts\test-run.ps1 -Exe ... -Options '-SeriesS' -More @{VICTORY_JOIN_PARTS='8'}  # same options as the launcher
```

Play in the same place, the same route, each time. Note the start time and when anything looked
wrong. Quit from the game's menu where you can.

| Run | Length | Purpose |
|---|---|---|
| Boot | until the menu | Starts? Adapter, DLSS and driver lines. |
| Short | 5 minutes in one scene | Frame rate, first stutter. |
| Soak | 30 minutes | RAM and VRAM growth, device loss, long-run stutter. |
| Capture | one frame | Where a slow frame spends its time (below). |

**One frame.** Record it in a `diag` build and replay it without the game: see [replay.md](replay.md)
and foxhound's notes in [README-foxhound.md](README-foxhound.md).

## 5. What to send back

1. The whole log file, the driver version, and the options or F1 settings used.
2. The frame rate from the F3 panel in a fixed place.
3. The line "errors the graphics driver reported to the system since the start", if it appears.
4. Peak RAM and VRAM (F3 panel or Task Manager).
5. What looked wrong on screen, and roughly where.

## 6. Troubleshooting

| Symptom | Try |
|---|---|
| Out of memory | Page file. Series S (`-SeriesS`). Close other programs. |
| Device lost / driver reset | Leave frame generation off. Keep the log: the driver watch logs the driver's own error and switches the indirect-window path off. |
| Frame generation shows nothing | HAGS on, window focused, FidelityFX DLLs present. On a full 12 GB card, VRAM may be past the budget: Series S or a lower picture size. |
| Stutter on a new build | `-Preload` once. |
| Scripts blocked | `Get-ChildItem -Recurse \| Unblock-File`, or start with `powershell -ExecutionPolicy Bypass -File ...`. |
