# Starts the title with the settings this fork is played with (README.md, "How to run it").
#   scripts\play.ps1 -Exe <path of your own copy's executable>
# -Safe         without the newer, faster ways (the first thing to try when something is wrong)
# -RayTracing   the title's own ray-traced indirect light: lit interiors, about a third slower
# -Build        target\diag (the default, the build all measurements are of) or target\release
# -WideIndirect lets the card try indirect dispatches past 65,535 groups: untested, may lose the device
# -InPlaceProbe asks this PC's driver whether title memory can be opened as card memory (VICTORY_INPLACE_PROBE=1); read the log
# -InPlace      title memory used in place, not copied (VICTORY_INPLACE=1, 2 GB at most): off until the probe passes
# -Settings     shows the settings window (also shown on the first run); choices are saved and used by later runs
# -NoDialog     never shows it: command-line switches and the saved choices (or the defaults) only
# -More         other settings: -More @{VICTORY_PANEL='1'}
# Run it from a normal window, not as administrator: the driver then keeps its shader cache elsewhere.
param(
    [string]$Exe,
    [switch]$Settings,
    [switch]$NoDialog,
    [switch]$Safe,
    [switch]$RayTracing,
    [ValidateSet('diag', 'release')][string]$Build = 'diag',
    [switch]$WideIndirect,
    [switch]$InPlaceProbe,
    [switch]$InPlace,
    [hashtable]$More = @{}
)
. (Join-Path $PSScriptRoot 'Settings.ps1')
# The settings window: on the first run, when asked for (-Settings), and when there is no game executable yet.
$cfg = Get-LauncherConfig
if (-not $NoDialog -and ($Settings -or -not $cfg -or (-not $Exe -and -not $cfg.exe))) {
    $cfg = Show-LauncherSettings $cfg $Exe
    if (-not $cfg) { Write-Host 'Cancelled.'; exit 0 }
    Save-LauncherConfig $cfg
}
if (-not $cfg) { $cfg = Get-LauncherDefaults }
if (-not $Exe) { $Exe = [string]$cfg.exe }
# What the command line says wins over what was saved; switches only ever add.
if ($cfg.safe) { $Safe = $true }
if ($cfg.rayTracing -ne 'off') { $RayTracing = $true }
if ($cfg.inPlace) { $InPlace = $true }
if ($cfg.wideIndirect) { $WideIndirect = $true }
if (-not $PSBoundParameters.ContainsKey('Build')) { $Build = [string]$cfg.build }
$settings = @{
    VICTORY_TEXTURE_NO_WAIT = '1'; VICTORY_RELAY = '2'; VICTORY_WIDE_BACK = '1'; VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_JOIN_COPIES = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_RELAY_COPY = '1'; VICTORY_CARD_STEPS = '2'
    VICTORY_INDIRECT_BATCH = '2'; VICTORY_MAP_THREADS = '1'; VICTORY_TITLE_PRIORITIES = '0'; VICTORY_CARD_AWAKE = '1'
    VICTORY_SHOW_AFTER = '1'; VICTORY_AMBIENT = '0.8'; VICTORY_D3D12_DRED = 'light'
}
# This fork is for NVIDIA cards only: it asks for the NVIDIA adapter, and says so if there is none.
$names = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object Name)
if (-not ($names -match 'NVIDIA')) { Write-Host "Warning: no NVIDIA adapter found (seen: $($names -join ', ')). This fork is made for NVIDIA cards only." }
# The title's own threads and ours share the CPU: the settings below were made for 24 threads (8 and 8).
$workers = [Math]::Max(2, [Math]::Min(8, [int][Math]::Floor([Environment]::ProcessorCount / 3)))
if ($Safe) {
    $settings.VICTORY_UNDER_WIDE = '0'; $settings.VICTORY_LAND_ECHO = '0'
} else {
    $settings.VICTORY_THIN = '1'; $settings.VICTORY_UPLOAD_AHEAD = '1'
    $settings.VICTORY_JOIN_PARTS = "$workers"; $settings.VICTORY_THIN_THREADS = "$workers"   # 8 and 8 on 24 threads
}
if ($RayTracing) { $settings.VICTORY_BVH_BUILDER = '1' }
if ($InPlaceProbe) { $settings.VICTORY_INPLACE_PROBE = '1' }
# Starting points for 12 GB of VRAM and 32 GB of RAM; none of these is measured yet.
$settings.VICTORY_D3D12_ADAPTER = 'NVIDIA'
if ($InPlace) { $settings.VICTORY_INPLACE = '1'; $settings.VICTORY_INPLACE_MB = '2048' }
$settings.VICTORY_LEVELS_ON_DEMAND = '1'   # card memory only for texture levels the title holds (about 3 GB saved in the 12 GB RTX 4070 test)
$settings.VICTORY_RESIDENCY = '1'          # low-RAM budgets: list retirement lag 16 not 64, no 5-minute scratch cache, texture prefetch under pressure, idle staging let go
$settings.VICTORY_WINDOW_BUDGET_MB = '4096' # caps loose title-window copies (about 7 GB uncapped); halved in the High RAM band
if ($WideIndirect) { $settings.VICTORY_INDIRECT_WIDE = 'force' }
# The settings window's choices.
if ($cfg.output -ne 'default') { $settings.VICTORY_OUTPUT = [string]$cfg.output }
if ($cfg.fps -eq '60') { $settings.VICTORY_FRAME_INTERVAL_MS = '16.667' }
if ($cfg.fps -eq '45') { $settings.VICTORY_FRAME_INTERVAL_MS = '22.222' }
if ($cfg.rayTracing -eq 'ambient') { $settings.VICTORY_AMBIENT_RT = '0.7,1.5' }
if ($cfg.memory -eq 'low') { $settings.VICTORY_RESIDENCY = '1'; $settings.VICTORY_WINDOW_BUDGET_MB = '2048' }
if ($cfg.memory -eq 'balanced') { $settings.VICTORY_RESIDENCY = '1'; $settings.VICTORY_WINDOW_BUDGET_MB = '4096' }
if ($cfg.memory -eq 'high') { $settings.VICTORY_RESIDENCY = '0'; $settings.Remove('VICTORY_WINDOW_BUDGET_MB') }
foreach ($k in $More.Keys) { $settings[$k] = $More[$k] }

$victory = Join-Path $PSScriptRoot "..\target\$Build\victory.exe"
if (-not (Test-Path $victory)) { Write-Host "No $victory. Build it first (README.md)."; exit 1 }
if (-not $Exe -or -not (Test-Path $Exe)) { Write-Host "No game executable ($Exe). Run with -Settings to choose it."; exit 1 }
# (Other settings left over in this window go; where your files are stays.)
$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR'
$inherited = @(Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths })
foreach ($entry in $inherited) { Remove-Item "Env:$($entry.Name)" }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
$discarded = $inherited | Where-Object {
    $_.Name -notin $More.Keys -and -not $_.Value.Equals([Environment]::GetEnvironmentVariable($_.Name))
} | Sort-Object Name
if ($discarded) {
    Write-Host "Discarded inherited values for $($discarded.Name -join ', '). Use -More to pass them explicitly."
}
$Exe = (Resolve-Path $Exe).Path
Push-Location (Join-Path $PSScriptRoot '..')   # victory.toml is looked for here
try { & $victory run $Exe --execute --console ([string]$cfg.console) } finally { Pop-Location }
