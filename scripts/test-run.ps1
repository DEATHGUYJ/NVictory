# NVictory: runs the game for a fixed time through play-foxhound.ps1, then closes it and prints the log lines to send.
#   scripts\test-run.ps1 -Exe 'D:\MyCopy\game_scarlett_master.exe'
#   scripts\test-run.ps1 -Exe ... -Minutes 30 -Build diag
#   scripts\test-run.ps1 -Exe ... -More @{VICTORY_JOIN_PARTS='8'}
# -Minutes  how long to play before closing it (default 5)
# -Build    release (default, what you play) or diag (slower; counters and captures)
# -Options   more options for play-foxhound.ps1, e.g. -Options '-SeriesS -Dlss balanced'
# -More     switches passed through, as play-foxhound.ps1's -More
# The launcher writes its log to %LOCALAPPDATA%\victory\logs\victory-nvidia-<date>.log; this script reads the newest.
# It asks the game window to close first, so the end-of-run lines can print; after 30 seconds it is stopped.
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Minutes = 5,
    [ValidateSet('diag', 'release')][string]$Build = 'release',
    [string]$Options = '',
    [hashtable]$More = @{}
)
$ErrorActionPreference = 'Stop'
if ($Minutes -lt 1) { $Minutes = 1 }
$play = Join-Path $PSScriptRoot 'play-foxhound.ps1'
$logs = Join-Path $env:LOCALAPPDATA 'victory\logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

$cmd = "& '$play' -Exe '$Exe' -Build $Build $Options"
if ($More.Count -gt 0) {
    $pairs = @($More.Keys | ForEach-Object { "'$_'='$($More[$_])'" }) -join ';'
    $cmd += " -More @{$pairs}"
}
$started = Get-Date
Write-Host "Starting at $($started.ToString('HH:mm:ss')); it will be closed after $Minutes minute(s)."
$child = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Normal `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "`"$cmd`"")

$deadline = $started.AddMinutes($Minutes)
while ((Get-Date) -lt $deadline -and -not $child.HasExited) { Start-Sleep -Seconds 2 }
if (-not $child.HasExited) {
    Write-Host 'Time is up: asking the game to close.'
    foreach ($p in @(Get-Process -Name 'victory' -ErrorAction SilentlyContinue)) { [void]$p.CloseMainWindow() }
    $limit = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $limit -and -not $child.HasExited) { Start-Sleep -Seconds 1 }
    if (-not $child.HasExited) {
        Write-Host 'It did not close in 30 seconds: stopping it (the log will have no end-of-run lines).'
        & taskkill.exe /PID $child.Id /T /F | Out-Null
        foreach ($p in @(Get-Process -Name 'victory' -ErrorAction SilentlyContinue)) { & taskkill.exe /PID $p.Id /T /F | Out-Null }
    }
}
$ended = Get-Date
Start-Sleep -Seconds 1
$log = Get-ChildItem -Path $logs -Filter 'victory-nvidia-*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $started } | Sort-Object LastWriteTime | Select-Object -Last 1
Write-Host ''
Write-Host ("Ran {0:N1} minutes." -f ($ended - $started).TotalMinutes)
if (-not $log -or $log.Length -eq 0) {
    Write-Host "No log from this run in $logs : the game may not have started. Run play-foxhound.ps1 by hand."
    exit 1
}
Write-Host "Log: $($log.FullName)"
Write-Host ''
Write-Host 'Lines to send back (last of each kind):'
$pattern = 'fps|frame account|recording and mapping waits|graphics driver reported|dropped|device (was )?(lost|removed)|panicked|out of memory|budget|error'
Select-String -Path $log.FullName -Pattern $pattern | Select-Object -Last 30 | ForEach-Object { $_.Line }
Write-Host ''
Write-Host "Send the whole file, the driver version, and what looked wrong on screen."
