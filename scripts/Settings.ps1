# The launcher's settings screen (scripts\play.ps1 dot-sources this file; it is not run on its own).
# Choices are saved to %LOCALAPPDATA%\victory\launcher.json and turned into VICTORY_* settings by play.ps1.
# Windows PowerShell 5.1 and PowerShell 7 on Windows; ASCII only, as 5.1 reads this file in the ANSI code page.

function Get-LauncherConfigPath {
    Join-Path $env:LOCALAPPDATA 'victory\launcher.json'
}

function Get-LauncherDefaults {
    [ordered]@{
        exe          = ''
        console      = 'series-x' # series-x, series-s
        output       = 'default'  # default or one of the title's display modes
        fps          = '30'       # 30 (title default), 45, 60
        rayTracing   = 'off'      # off, on, ambient
        memory       = 'auto'     # auto, low, balanced, high
        build        = 'diag'     # diag, release
        safe         = $false
        inPlace      = $false
        wideIndirect = $false
    }
}

# The saved choices over the defaults, or $null if none were saved (or the file cannot be read).
function Get-LauncherConfig {
    $path = Get-LauncherConfigPath
    if (-not (Test-Path $path)) { return $null }
    try { $json = Get-Content -Raw -Path $path | ConvertFrom-Json } catch { return $null }
    $config = Get-LauncherDefaults
    foreach ($p in $json.PSObject.Properties) {
        if ($config.Contains($p.Name)) { $config[$p.Name] = $p.Value }
    }
    $config
}

function Save-LauncherConfig {
    param([Parameter(Mandatory)]$Config)
    $path = Get-LauncherConfigPath
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    $Config | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
}

# Shows the settings window. Returns the chosen settings (an ordered hashtable), or $null if cancelled.
function Show-LauncherSettings {
    param($Current, [string]$Exe)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $config = Get-LauncherDefaults
    if ($Current) { foreach ($k in @($config.Keys)) { if ($Current.Contains($k)) { $config[$k] = $Current[$k] } } }
    if ($Exe) { $config.exe = $Exe }

    # key, label, the values saved, the names shown
    $rows = @(
        @{ key = 'console'; label = 'Console profile'
           vals = @('series-x', 'series-s')
           names = @('Series X (full detail)', 'Series S (1080p, a few ms faster, softer, less RAM)') },
        @{ key = 'output'; label = 'Output size (Series X)'
           vals = @('default', '1280x720', '1664x936', '1920x1080', '2560x1440', '3840x2160')
           names = @('The title''s own choice', '1280 x 720', '1664 x 936', '1920 x 1080 (about 16 ms less card time)', '2560 x 1440', '3840 x 2160') },
        @{ key = 'fps'; label = 'Frame rate the title may reach'
           vals = @('30', '45', '60')
           names = @('30 (the title''s own)', '45', '60 (menus and videos; the world is limited by the CPU)') },
        @{ key = 'rayTracing'; label = 'Ray tracing'
           vals = @('off', 'on', 'ambient')
           names = @('Off', 'On (about a third slower)', 'On, with the ambient light stand-in (no black rooms)') },
        @{ key = 'memory'; label = 'Memory use'
           vals = @('auto', 'low', 'balanced', 'high')
           names = @('Automatic (low-RAM budgets at 32 GB or less)', 'Low (tightest; more copying, 32 GB PCs)', 'Balanced', 'High (64 GB PCs; most memory kept)') },
        @{ key = 'build'; label = 'Build to run'
           vals = @('diag', 'release')
           names = @('diag (logs, VICTORY_PANEL, memory map)', 'release (no diagnostics; for playing)') }
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'VIctory settings'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.AutoSize = $true
    $form.AutoSizeMode = 'GrowAndShrink'
    $form.Padding = New-Object System.Windows.Forms.Padding(12)

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.ColumnCount = 2
    $table.AutoSize = $true
    $table.AutoSizeMode = 'GrowAndShrink'
    $form.Controls.Add($table)

    $newLabel = {
        param($text)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text
        $l.AutoSize = $true
        $l.Anchor = 'Left'
        $l.Margin = New-Object System.Windows.Forms.Padding(3, 8, 12, 3)
        $l
    }

    # The game's executable: a box and a Browse button.
    $table.Controls.Add((& $newLabel 'Game executable'))
    $exePanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $exePanel.AutoSize = $true
    $exeBox = New-Object System.Windows.Forms.TextBox
    $exeBox.Width = 300
    $exeBox.Text = [string]$config.exe
    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'Browse...'
    $browse.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'Executables (*.exe)|*.exe|All files (*.*)|*.*'
        if ($dialog.ShowDialog() -eq 'OK') { $exeBox.Text = $dialog.FileName }
    }.GetNewClosure())
    $exePanel.Controls.Add($exeBox)
    $exePanel.Controls.Add($browse)
    $table.Controls.Add($exePanel)

    $combos = @{}
    foreach ($r in $rows) {
        $table.Controls.Add((& $newLabel $r.label))
        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.DropDownStyle = 'DropDownList'
        $combo.Width = 360
        foreach ($n in $r.names) { [void]$combo.Items.Add($n) }
        $table.Controls.Add($combo)
        $combos[$r.key] = $combo
    }

    $checks = @{}
    $checkRows = @(
        @{ key = 'safe'; text = 'Safe mode: leave out the newest, faster ways (try this first when something is wrong)' },
        @{ key = 'inPlace'; text = 'Use title memory in place (NVIDIA; run the in-place probe first, see README)' },
        @{ key = 'wideIndirect'; text = 'Let the card try very wide indirect dispatches (NVIDIA; untested, may lose the device)' }
    )
    foreach ($c in $checkRows) {
        $box = New-Object System.Windows.Forms.CheckBox
        $box.Text = $c.text
        $box.AutoSize = $true
        $box.Margin = New-Object System.Windows.Forms.Padding(3, 6, 3, 0)
        $table.Controls.Add($box)
        $table.SetColumnSpan($box, 2)
        $checks[$c.key] = $box
    }

    # Puts the values of $values (a hashtable) into the controls.
    $fill = {
        param($values)
        foreach ($r in $rows) {
            $index = [array]::IndexOf([string[]]$r.vals, [string]$values[$r.key])
            if ($index -lt 0) { $index = 0 }
            $combos[$r.key].SelectedIndex = $index
        }
        foreach ($key in $checks.Keys) { $checks[$key].Checked = [bool]$values[$key] }
    }.GetNewClosure()
    & $fill $config

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.AutoSize = $true
    $buttons.Margin = New-Object System.Windows.Forms.Padding(3, 12, 3, 3)
    $play = New-Object System.Windows.Forms.Button
    $play.Text = 'Save and play'
    $play.Width = 110
    $play.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = 'Cancel'
    $preset = New-Object System.Windows.Forms.Button
    $preset.Text = '32 GB PC preset'
    $preset.Width = 110
    $preset.Add_Click({
        # What the notes suggest for 32 GB of RAM: the Series S profile at 1080p, ray tracing off, tight memory.
        $values = Get-LauncherDefaults
        $values.exe = $exeBox.Text
        $values.console = 'series-s'
        $values.output = '1920x1080'
        $values.memory = 'low'
        & $fill $values
    }.GetNewClosure())
    $reset = New-Object System.Windows.Forms.Button
    $reset.Text = 'Defaults'
    $reset.Add_Click({
        $values = Get-LauncherDefaults
        $values.exe = $exeBox.Text
        & $fill $values
    }.GetNewClosure())
    foreach ($b in @($play, $cancel, $preset, $reset)) { $buttons.Controls.Add($b) }
    $table.Controls.Add($buttons)
    $table.SetColumnSpan($buttons, 2)
    $form.AcceptButton = $play
    $form.CancelButton = $cancel

    # Saving needs a game executable that exists.
    $form.Add_FormClosing({
        param($sender, $e)
        if ($sender.DialogResult -eq 'OK' -and -not (Test-Path -LiteralPath $exeBox.Text -PathType Leaf)) {
            [void][System.Windows.Forms.MessageBox]::Show('Choose the game executable first.', 'VIctory settings')
            $e.Cancel = $true
        }
    }.GetNewClosure())

    $answer = $form.ShowDialog()
    if ($answer -ne 'OK') { return $null }
    $chosen = Get-LauncherDefaults
    $chosen.exe = $exeBox.Text
    foreach ($r in $rows) { $chosen[$r.key] = $r.vals[$combos[$r.key].SelectedIndex] }
    foreach ($key in $checks.Keys) { $chosen[$key] = [bool]$checks[$key].Checked }
    $chosen
}
