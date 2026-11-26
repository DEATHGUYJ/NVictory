# Runs the game for a fixed time with the log saved, then closes it.
#   scripts\test-run.ps1 -Exe <path of your copy's executable>
#   scripts\test-run.ps1 -Minutes 5 -Safe
# -Exe       the game's executable (default: the one saved by play.ps1's settings window)
# -Minutes   how long to play before closing it (default 5)
# -Safe      passed to play.ps1: without the newer, faster ways
# -Build     diag (default, has the counters) or release
# -More      passed to play.ps1, e.g. -More @{VICTORY_PANEL='1'}
# The log goes to %LOCALAPPDATA%\victory\logs\test-<date>.log (with .err.log beside it).
# It asks the game to close first, so its end-of-run summary can print; after 30 seconds it is stopped.
# Run it from a normal window, not as administrator. Play in the same place each time to compare runs.
param(
    [string]$Exe,
    [int]$Minutes = 5,
    [switch]$Safe,
    [ValidateSet('diag', 'release')][string]$Build = 'diag',
    [hashtable]$More = @{}
)
$ErrorActionPreference = 'Stop'
if ($Minutes -lt 1) { $Minutes = 1 }
$play = Join-Path $PSScriptRoot 'play.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'victory\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $logDir "test-$stamp.log"
$err = Join-Path $logDir "test-$stamp.err.log"

# The command for play.ps1 (-NoDialog: never show the settings window in a timed run).
# It is run with -Command, so that a -More hashtable arrives as a hashtable.
$cmd = "& '$play' -NoDialog -Build $Build"
if ($Exe) { $cmd += " -Exe '$Exe'" }
if ($Safe) { $cmd += ' -Safe' }
if ($More.Count -gt 0) {
    $pairs = @($More.Keys | ForEach-Object { "'$_'='$($More[$_])'" }) -join ';'
    $cmd += " -More @{$pairs}"
}
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "`"$cmd`"")

$started = Get-Date
Write-Host "Starting at $($started.ToString('HH:mm:ss')); it will be closed after $Minutes minute(s)."
Write-Host "Log: $err"
$child = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -PassThru -WindowStyle Normal `
    -RedirectStandardOutput $out -RedirectStandardError $err

# Wait for the time to pass, or for the game to end by itself.
$deadline = $started.AddMinutes($Minutes)
while ((Get-Date) -lt $deadline -and -not $child.HasExited) { Start-Sleep -Seconds 2 }

if (-not $child.HasExited) {
    Write-Host 'Time is up: asking the game to close.'
    $game = @(Get-Process -Name 'victory' -ErrorAction SilentlyContinue)
    foreach ($p in $game) { [void]$p.CloseMainWindow() }
    $limit = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $limit -and -not $child.HasExited) { Start-Sleep -Seconds 1 }
    if (-not $child.HasExited) {
        Write-Host 'It did not close in 30 seconds: stopping it (the log will have no end-of-run summary).'
        & taskkill.exe /PID $child.Id /T /F | Out-Null
    }
}
$ended = Get-Date
Start-Sleep -Seconds 1

Write-Host ''
Write-Host ("Ran {0:N1} minutes." -f ($ended - $started).TotalMinutes)
Write-Host "Logs: $out"
Write-Host "      $err"
if (-not (Test-Path $err) -or (Get-Item $err).Length -eq 0) {
    Write-Host 'The log is empty: the game may not have started. Check the .log file and run play.ps1 by hand.'
    exit 1
}
Write-Host ''
Write-Host 'Lines to send back:'
$pattern = 'frame account|recording and mapping waits|graphics driver reported|device (was )?(lost|removed)|panicked|out of memory|error'
Select-String -Path $err, $out -Pattern $pattern | Select-Object -Last 25 | ForEach-Object { $_.Line }
Write-Host ''
Write-Host "Also note the driver version and what looked wrong on screen. Send $err (the whole file)."
