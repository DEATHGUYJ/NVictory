# NVictory

VIctory for NVIDIA, set up for an RTX 3080 12 GB.

**Quick links:** [testing and running a game](docs/testing-and-running.md) · [replaying a frame](docs/replay.md) · [findings](docs/findings.md) · [architecture](docs/architecture.md)

A fork of [VIctory](https://github.com/Marvisak/VIctory), a compatibility layer
that runs an Xbox Series title natively on Windows from files the user supplies.
This fork is set up for **one PC: RTX 3080 12 GB, Ryzen 5 5600T (6 cores, 12
threads), 32 GB RAM.** It is NVIDIA-only: the AMD vendor checks, the AMD-only
FSR 4K mode and the AMD launcher profile are gone, and the launcher always asks
for the NVIDIA adapter. It started from an RX 7900 XTX fork; that card's numbers
are kept below, marked as such. (The console's own AMD GPU code, which the
translator reads, stays: it is the game's, not the host's.)

## Status: not yet run on the 3080

Nothing here has been measured on this PC. The launcher's NVIDIA settings and
the notes below are starting points worked out from the code and from the
measurements the AMD fork and an RTX 4070 12 GB run (older code) made. Expect to
tune. Please report what happens: the first useful thing to learn is whether it
boots, the second what a frame costs (`VICTORY_PANEL=1` shows it).

**This repository contains no game files, code or assets.** You need your own
copy of the game. It is not affiliated with or endorsed by the game's developer
or publisher.

## What to send back after the first run

A `diag` build prints, once a frame batch, a line starting "recording and mapping waits per
frame": how long host state preludes take to record, and how long changes of title mapping
and reads of title memory wait for each other (the global remap lock). With the frame
account line and `VICTORY_MEMORY_MAP=1`, that says whether DexNom/VIctory's parallel
prelude recording or its per-range remap lock would help this PC. If the waits are under
about 1 ms a frame, they would not.

## What changed in this fork (summary)

- **NVIDIA only.** No AMD vendor checks, no AMD launcher profile, no AMD-only FSR 4K mode.
- **Low-RAM defaults** for PCs with 32 GB or less (`residency.rs`), plus an optional in-place
  title-memory mode behind a probe.
- **Launcher and settings window** (`scripts\play.ps1`, `scripts\Settings.ps1`): choices are
  saved, and the NVIDIA settings are always applied. Worker counts follow the CPU.
- **Safer submission defaults on NVIDIA:** `VICTORY_THIN` and `VICTORY_JOIN_PARTS` are off (missing head
  skin and repeated video frames on NVIDIA in DoubleGhosty/cool_fox); `-Async` turns them on for speed.
- **Driver watch** (`drvwatch.rs`, from VItoriaBr): NVIDIA's event-log errors (event 153) are
  logged; the first one switches the indirect-window path off for the rest of the run.
  `VICTORY_DRIVER_WATCH=0` turns it off.
- **Diagnostics counters** for recording and mapping waits, to decide on later ports.
- Clippy is clean for the Windows target. Nothing has run on the 3080 yet.

## What the 3080 has and what it does not

| | |
|---|---|
| Direct3D 12 SM 6.6, mesh shaders, DXR | yes (Ampere); the title's requirements are met |
| Waves of 32 | handled: console wave64 compute is translated for 32 lanes (`victory-gpu/src/host.rs`) |
| Heap cap of 1,000,000 views, 16-bit colour formats, R9G9B9E5 | handled by clamps and stand-in formats (`descriptor/host.rs`, `resource.rs`) |
| Indirect dispatches over 65,535 groups | **cut off** unless `-WideIndirect` (below): a few thousand of the picture's lowest tiles can go missing |
| 12 GB of VRAM | the AMD run used 10.5 GB, the 4070's run sat at 85-99 % of its budget: texture churn likely |
| 32 GB of RAM | **short**: the AMD run used about 30 GB of private memory and the notes in `docs/findings.md` count 40-46 GB (lists' allocators 9, windows 7, uploads 4). Set a large page file (see below) |
| 6 cores / 12 threads | the AMD run had 24 threads. Thread counts that follow the CPU scale down by themselves; the launcher leaves `VICTORY_THIN` and `VICTORY_JOIN_PARTS` off on NVIDIA, and `-Async` turns them on with 4 workers. The frame is limited by the one thread that submits (about 40 ms there), so single-core speed matters most |

## How to run it

A ready-built `victory.exe` (diag and release) is attached to every **Build** run in the Actions
tab; see [the testing guide](docs/testing-and-running.md#2-build-or-download-a-ready-build).
To build it yourself you need Windows 10/11 x64, a CPU with AVX2 (the 5600T has it), the MSVC build
tools, Rust (the toolchain is pinned), the current NVIDIA driver, and your own
dump of the title.

Set the **page file** first: at least 32-48 GB on an NVMe drive (System
Properties, Advanced, Performance, Virtual memory). With 32 GB of RAM the
title's private memory will not all fit, and without it the run ends in an
out-of-memory error rather than a slow frame.

```powershell
git clone https://github.com/DEATHGUYJ/NVictory
cd NVictory
copy victory.example.toml victory.toml      # then set game_dir, outside this folder
cargo build --locked --profile diag -p victory --features diagnostics
target\diag\victory.exe shaders <the shader archives>   # every shader translated, minutes
target\diag\victory.exe warm --used                     # pipelines for this driver and build
scripts\play.ps1 -Exe <path of your copy's executable>
```

Run it from a normal window, not as administrator. Try `-Safe` first when
something is wrong. Close the browser and other programs: every GB counts.

**Settings window.** The first run of `scripts\play.ps1` opens a window (Windows Forms,
nothing to build): game executable, console profile (Series X or
S), output size, frame rate (30, 45 or 60), ray tracing, memory use (automatic, low,
balanced or high), build (diag or release) and the safe-mode, in-place and wide-indirect
boxes. A **32 GB PC preset** button picks the Series S profile at 1080p with tight
memory. Choices are saved in `%LOCALAPPDATA%\victory\launcher.json` and used by later
runs; `-Settings` opens the window again and `-NoDialog` never shows it. A switch on the
command line adds to what was saved (`-Build` and `-Exe` replace it). The window
has not been run on Windows yet.

What the launcher sets for the NVIDIA card, on top of the usual settings (all unmeasured starting
points, change them with `-More @{NAME='value'}`):

| Setting | Value | Why |
|---|---|---|
| `VICTORY_D3D12_ADAPTER` | `NVIDIA` | picks the 3080 on a PC with a second adapter (such as an iGPU) |
| `VICTORY_THIN`, `VICTORY_JOIN_PARTS` | `0` (off) | another NVIDIA fork (DoubleGhosty/cool_fox) found head skin not drawn with `THIN` and repeated video frames with `JOIN_PARTS`. `-Async` turns both on, with one third of the PC's threads (4 on your 12) |
| `VICTORY_LEVELS_ON_DEMAND` | `1` | the card holds only the texture levels the title holds; about 3 GB saved in the 4070's run, which had no device loss |
| `VICTORY_RESIDENCY` | `1` | the fork's low-RAM mode (also on by itself at 32 GiB of RAM or less; `0` turns it off): finished command lists and retired objects wait 16 submissions, not 64, before they are freed (`VICTORY_BURY_LAG`; the lists' allocators were about 9 GB in the AMD run, how much this saves is not measured); idle scratch and staging blocks are not kept for five minutes; texture prefetch is cut to 128 MiB a frame and to 64 / 16 MiB when free RAM or commit runs low |
| `VICTORY_WINDOW_BUDGET_MB` | `4096` | caps the loose title-window copies (about 7 GB uncapped); the cap is halved when the process holds half the RAM, which on 32 GB will be most of the time |

**Using title memory in place (the closest a PC gets to the console's one memory).**
`VICTORY_INPLACE=1` opens a part of the title's own memory as a Direct3D heap and
places the buffer over it, so shaders read and write the title's bytes and no
host copy stands between: less RAM (the windows of title memory were about 7 GB)
and no refreshes of those copies. It is off by default and has not run on an NVIDIA
card. The card then reads that memory over PCIe, and the heap call it needs
(`OpenExistingHeapFromAddress1`) is a newer driver feature, so check first:

1. `scripts\play.ps1 -Exe <path> -InPlaceProbe`: the log says what this driver makes of the
   two openings (`VICTORY_INPLACE_PROBE=1`, `docs/README-fxceless.md`).
2. Only if it passes: `-InPlace` (stage 1, windows outside buffers, at most 2 GB:
   `VICTORY_INPLACE_MB`). Stage 2 (`VICTORY_INPLACE=2`, title buffers too) is not
   combined with `VICTORY_LATE_WAIT`; try it last, with `-More @{VICTORY_INPLACE='2'}`.
3. A device loss or a worse frame time: leave it off.

If it runs out of memory or the picture shows missing tiles at the bottom of the
frame, these are the first things to try:

- `-More @{VICTORY_WINDOW_BUDGET_MB='2048'}`, `VICTORY_BURY_LAG=8` (frees finished lists sooner;
  the lag exists because of device losses from memory freed too early, so lower it only to test)
  and `VICTORY_KEEP_SNAPSHOTS_MB=128`, for less RAM; `VICTORY_MEMORY_MAP=1` lists where it goes.
- `-WideIndirect` (sets `VICTORY_INDIRECT_WIDE=force`) lets the card try indirect
  dispatches of up to about a million groups. D3D12 leaves
  counts past 65,535 undefined, so an NVIDIA card may clamp them, wrap them or lose
  the device. It is off by default for that reason. Try it only if tiles are missing.
- `VICTORY_OUTPUT=1920x1080` or `--console series-s` (see the tables below) for
  less card time and less memory.
- Ray tracing (`-RayTracing`) is untested here and about a third slower; leave it off first.

On a hybrid-graphics PC, the runtime and offline pipeline checks prefer a
high-performance adapter with Shader Model 6.6. The runtime logs its adapter
name, PCI vendor and device IDs, and dedicated VRAM. Set `VICTORY_D3D12_ADAPTER`
to a zero-based DXGI index or part of the adapter's name to select it explicitly.

Testing the build and running a game, step by step: [docs/testing-and-running.md](docs/testing-and-running.md).
Commands, debugging switches and upstream's own description:
[docs/README-fxceless.md](docs/README-fxceless.md). Every `VICTORY_...` switch is
described in a comment where it is read.

## Goal

**A stable 30 fps or more without ray tracing, then as high a frame rate and as
low frame times as the PC allows.** The way there is **porting, not emulating**:
patching the title's renderer so it behaves the way a PC renderer does, rather
than having the layer watch and copy the console's shared memory every frame.
Shaders are translated ahead of time into a versioned store that is kept between
builds. Ray tracing stays optional and off by default.

## Measured elsewhere (RX 7900 XTX, not this PC)

Tested on one machine only: Windows 11, Intel i9-12900K, 64 GB RAM, Radeon RX
7900 XTX, ray tracing off, as of 2026-11-26. These say what the code can do, not
what the 3080 will.

| | |
|---|---|
| City street, Series S profile, renderer patches 1, 2, 5, 6 and 7 on | about 45 ms a frame (about 22 fps) |
| Same, patches 1, 2 and 5 | 47.3 ms (about 21 fps), p95 49 ms |
| Series X profile, patches 1+2 | about 53 ms (about 19 fps) |
| Same scene before the patches | 57-75 ms (13-17 fps) |
| Shaders the title uses that translate | all of them (25,790 of 25,985; the rest are unused geometry shaders) |
| Memory | about 30 GB of private memory, 10.5 GB of VRAM |

An earlier state of the code (2026-11-25) ran at 2.5-4 fps on an RTX 4070 12 GB,
i7-14700KF, 32 GB ([docs/README-fxceless.md](docs/README-fxceless.md)).

### Fixes taken from avatarmanz/VIctory-7900XTX (2026-11-26)

- `VICTORY_PORT_CONSTANTS_ORDER` (on by default): indirect draws whose arguments sit in
  renderer patch 1's in-place memory are prepared one at a time right before they run.
  Without it, with `VICTORY_PORT_CONSTANTS=1`, trees and palms dropped out for a few frames
  and lamp-lit rooms swung between too dark and too bright. Needed before the patches below
  are turned on by default.
- `VICTORY_AMBIENT_RT=0.7,1.5` (off by default): stand-in for the indirect light with ray
  tracing, so rooms lit only by bounced light are not black.
- Their measurements (RX 7900 XTX, 64 GB): Series X 4K drawn at 1440p, ray tracing off,
  49 ms standing, about 62 ms walking, **45 GB of RAM**; Series S 43 / 64 ms, 37 GB.
  The 32 GB of this PC is below all of them.

### Renderer patches (off by default while they are tested)

| Switch | What it does |
|---|---|
| `VICTORY_PORT_CONSTANTS=1` | The title's 174 MB constants heap is read by the card where the title writes it: no uploads, no fills |
| `VICTORY_PORT_DESCRIPTORS=1` | The title's descriptor-table stores are patched (byte-checked) to report the slots they write, instead of a scan of ~600,000 slots a frame |
| `VICTORY_PORT_CBV=1` | Translated shaders read constant buffers in place as raw bytes (~22,000 fills a frame to none; -4.7 ms) |
| `VICTORY_PORT_GUARD=1` | The write guards' lock is shared by faults and refreshes, with a claim per 64 KiB block; the submission's planning runs beside it (title threads' waits 29 ms to ~2 ms a frame; -2 ms) |
| `VICTORY_PORT_JOURNAL=1` | The heaps' records are asked for at the title's submit, and the journal's notes are split into 64 parts with locks of their own (the submit thread's waits ~5 ms + 1 ms to ~0.3 ms; -1 to -3 ms) |

### Other switches

| Switch | What it does |
|---|---|
| `--console series-s` | The Series S profile: 1080p output, about 5 ms faster, a softer picture |
| `VICTORY_OUTPUT=1920x1080` | The title renders to that output size itself (Series X profile; about 16 ms less card time) |
| `VICTORY_FRAME_INTERVAL_MS=16.667` | Lets the title go above 30 fps (menus and videos reach 60; the game's clock stays right) |
| `VICTORY_AMBIENT_SETTLE` | How fast light settles after walking indoors (on by default, `250,3`; `0` turns it off) |
| `VICTORY_TEXTURE_STORE=1` | Converted textures kept between runs (about 8 ms a frame for now: off) |
| `VICTORY_DRIVER_WATCH` | `0`: do not watch the system event log for the display driver's errors (on by default) |
| `VICTORY_INDIRECT_WIDE` | `0`: indirect dispatches cut at 65,535 groups; `force`: let the card try wide counts (untested) |

What is known to be wrong:

- Trees, signs and far objects flicker in the distance in some places.
- Lighting is too bright or too dark after walking indoors, until the title has
  run for a while; rooms with little direct light are too dark without `-RayTracing`.
- Textures of what just came into view appear late while the title streams.
- The first run of a new build stutters while the driver makes pipelines
  (`victory warm` makes them ahead).
- Recording a frame in the world makes the title's own watchdog end it.
- On cards that do not take wide indirect counts, an indirect pass asks for about
  77,500 thread groups where one dispatch runs 65,535 (the rest is cut off).

## What is different here

In short; the reasons and the measurements are in [docs/findings.md](docs/findings.md).

- **List calls are written down, not carried out, on the title's threads**
  (`VICTORY_THIN`): eight threads of ours translate them.
- **Submissions are prepared by a thread of ours and joined**
  (`VICTORY_ASYNC_SUBMIT`, `VICTORY_JOIN_PARTS`), with what can be spread over
  threads spread: refreshes, compares (AVX2), descriptor records, landings.
- **What shaders wrote comes back beside the write guards**, by the dwords that
  changed, on a thread of its own (`VICTORY_RELAY`, `VICTORY_LAND`).
- **Buffer fills that need bytes still on the card are done on the card**
  (`VICTORY_CARD_STEPS`) instead of waiting for it.
- **The title's writes are caught more cheaply**: one view opened at a fault,
  blocks that rest, places in the title's code that look before they write.
- **Textures go up on a copy queue of their own** and a slot shows one only after
  its upload ran, which also ended a device loss that came every 15 minutes or so.
- **Boats float**: textures that shaders write and the title's CPU reads go back
  to title memory (from fxceless and Geckomacabre, on by default here).
- **Frame record and replay** with per-pass times and shader variants compared
  turn by turn ([docs/replay.md](docs/replay.md)).

## Credits

NVictory is maintained by **[DEATHGUYJ](https://github.com/DEATHGUYJ)** (Alex). It is a tree of
other people's work with more on top. The history is kept, and
commits taken from elsewhere name the commit and its author.

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its
  contributors: the loader, the runtime services, the Direct3D 12 back end and
  the shader recompiler.
- **[fxceless/victory-fork](https://github.com/fxceless/victory-fork)**: the fork
  this one started from, and the people whose pull requests it carries.
- **[DexNom/VIctory](https://github.com/DexNom/VIctory)**: ray tracing fixes,
  cube gradients, sparse textures.
- **[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)**:
  the ambient light idea, pipeline workers, and work by romainhedouin.
- **[FQY55kai/ZJOU-VICTORY](https://github.com/FQY55kai/ZJOU-VICTORY)**.
- **[myokex/victory-amd](https://github.com/myokex/victory-amd)**: the guard over
  every view of a page (with Spexivus, joroyt and tightfall), and Joshua Odom's
  reads into title memory.
- **Geckomacabre** and **cxy0072019-sketch**: the texture read-back.
- **[avatarmanz/VIctory-7900XTX](https://github.com/avatarmanz/VIctory-7900XTX)**: the commits
  merged on 2026-11-27, including the constant-buffer ordering fix for tree and lamp flicker
  (`VICTORY_PORT_CONSTANTS_ORDER`).
- **[uiliannn/VItoriaBr](https://github.com/uiliannn/VItoriaBr)**: the display-driver event-log
  watch (`drvwatch.rs`).
- **[DoubleGhosty/cool_fox](https://github.com/DoubleGhosty/cool_fox)**: the NVIDIA findings behind
  turning `VICTORY_THIN` and `VICTORY_JOIN_PARTS` off by default; no code of it is here.
- **[Kelvaroq](https://github.com/fablinoo/kelvaroq)** (Stellarr Studio) was read for its NVIDIA
  and memory work; no code of it is here.
- **[XCL](https://github.com/ivall/xcl)** (GPL-2.0-only) was read for how the same
  title behaves under another layer; no code of it is here.
- This fork's changes were made with [Claude Code](https://claude.com/claude-code).

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE); the one file that is not
covered is named in [docs/asset-policy.md](docs/asset-policy.md).
