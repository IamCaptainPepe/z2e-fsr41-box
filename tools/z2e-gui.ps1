# z2e-fsr41-box: Windows GUI (WinForms) поверх CLI tools/z2e-fsr41.ps1.
# Двойной клик: tools/Z2E-FSR41-Box.cmd. Терминал не нужен.
#   -Smoke    — собрать форму и выйти (CI: форма строится)
#   -SelfTest — прогнать fetch→install→doctor→uninstall на testdata/fake-game
#               с Z2E_FAKE_PAYLOAD=1 без окна (работает и на Linux pwsh)
param(
    [switch]$Smoke,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Cli      = Join-Path $PSScriptRoot 'z2e-fsr41.ps1'
$Pwsh     = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $Pwsh) { $Pwsh = 'pwsh' }

function Get-Z2EGuiConfigPath {
    # Windows: %LOCALAPPDATA%\z2e-fsr41\gui.json (тот же кэш, что у fetch)
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA }
            elseif ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME }
            else { Join-Path $HOME '.config' }
    Join-Path $base 'z2e-fsr41/gui.json'
}

function Read-Z2EGuiConfig {
    $p = Get-Z2EGuiConfigPath
    if (Test-Path $p -PathType Leaf) {
        try { return (Get-Content -Raw $p | ConvertFrom-Json) } catch { }
    }
    return $null
}

function Write-Z2EGuiConfig {
    param([string]$LastExe)
    $p = Get-Z2EGuiConfigPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
    @{ lastExe = $LastExe } | ConvertTo-Json | Set-Content -Path $p -Encoding UTF8
}

function Resolve-Z2EGamePaths {
    # Пользователь выбирает ФАЙЛ .exe. Папка — отказ.
    param([string]$ExePath)
    $t = if ($ExePath) { $ExePath.Trim().Trim('"') } else { '' }
    if (-not $t) { throw 'Select an .exe file' }
    if (Test-Path $t -PathType Container) { throw 'Select an .exe file' }
    if ($t -notmatch '(?i)\.exe$') { throw 'Select an .exe file' }
    if (-not (Test-Path $t -PathType Leaf)) { throw "File not found: $t" }
    $full = (Resolve-Path $t).Path
    [pscustomobject]@{ exe = $full; game = (Split-Path -Parent $full) }
}

function Invoke-Z2EAction {
    # Вызов CLI, stdout+stderr в лог. Возвращает @{ Code; Text }.
    param([string[]]$CliArgs)
    $out = & $Pwsh -NoProfile -File $Cli @CliArgs 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = ('' + $out).Trim() }
}

if ($SelfTest) {
    # Headless-проверка Browse→Install на фейковом payload (CI/Linux).
    $env:Z2E_FAKE_PAYLOAD = '1'
    $r = Resolve-Z2EGamePaths -ExePath (Join-Path $RepoRoot 'testdata/fake-game/game.exe')
    $steps = @(
        ,@('fetch')
        ,@('install', '--game', $r.game, '--exe', $r.exe, '--fsr', '4.1.1b', '--inject', 'dxgi')
        ,@('doctor', '--game', $r.game)
        ,@('uninstall', '--game', $r.game)
    )
    foreach ($s in $steps) {
        $res = Invoke-Z2EAction -CliArgs $s
        Write-Host "== $($s[0]) => exit $($res.Code)"
        Write-Host $res.Text
        if ($res.Code -ne 0) { exit 1 }
    }
    Write-Host 'SELFTEST OK'
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Z2E FSR 4.1 Box'
$form.Size = New-Object System.Drawing.Size(720, 520)
$form.MinimumSize = New-Object System.Drawing.Size(640, 460)
$form.StartPosition = 'CenterScreen'

$lblExe = New-Object System.Windows.Forms.Label
$lblExe.Text = 'Game EXE'
$lblExe.Location = New-Object System.Drawing.Point(12, 15)
$lblExe.AutoSize = $true
$form.Controls.Add($lblExe)

$txtExe = New-Object System.Windows.Forms.TextBox
$txtExe.Location = New-Object System.Drawing.Point(90, 12)
$txtExe.Size = New-Object System.Drawing.Size(470, 23)
$txtExe.Anchor = 'Top,Left,Right'
$form.Controls.Add($txtExe)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse…'
$btnBrowse.Location = New-Object System.Drawing.Point(570, 11)
$btnBrowse.Size = New-Object System.Drawing.Size(120, 25)
$btnBrowse.Anchor = 'Top,Right'
$form.Controls.Add($btnBrowse)

$lblExePath = New-Object System.Windows.Forms.Label
$lblExePath.Location = New-Object System.Drawing.Point(14, 38)
$lblExePath.Size = New-Object System.Drawing.Size(676, 15)
$lblExePath.ForeColor = 'DimGray'
$lblExePath.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
$lblExePath.Anchor = 'Top,Left,Right'
$form.Controls.Add($lblExePath)

$lblGameDir = New-Object System.Windows.Forms.Label
$lblGameDir.Location = New-Object System.Drawing.Point(14, 54)
$lblGameDir.Size = New-Object System.Drawing.Size(676, 15)
$lblGameDir.ForeColor = 'DimGray'
$lblGameDir.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
$lblGameDir.Anchor = 'Top,Left,Right'
$form.Controls.Add($lblGameDir)

$lblFsr = New-Object System.Windows.Forms.Label
$lblFsr.Text = 'FSR version'
$lblFsr.Location = New-Object System.Drawing.Point(12, 84)
$lblFsr.AutoSize = $true
$form.Controls.Add($lblFsr)

$cmbFsr = New-Object System.Windows.Forms.ComboBox
$cmbFsr.Location = New-Object System.Drawing.Point(110, 80)
$cmbFsr.Size = New-Object System.Drawing.Size(110, 24)
$cmbFsr.DropDownStyle = 'DropDownList'
[void]$cmbFsr.Items.AddRange(@('4.1.1b', '4.1.1', '4.0.2c'))
$cmbFsr.SelectedIndex = 0
$form.Controls.Add($cmbFsr)

$lblInject = New-Object System.Windows.Forms.Label
$lblInject.Text = 'Inject'
$lblInject.Location = New-Object System.Drawing.Point(245, 84)
$lblInject.AutoSize = $true
$form.Controls.Add($lblInject)

$cmbInject = New-Object System.Windows.Forms.ComboBox
$cmbInject.Location = New-Object System.Drawing.Point(310, 80)
$cmbInject.Size = New-Object System.Drawing.Size(110, 24)
$cmbInject.DropDownStyle = 'DropDownList'
[void]$cmbInject.Items.AddRange(@('dxgi', 'winmm', 'version'))
$cmbInject.SelectedIndex = 0
$form.Controls.Add($cmbInject)

$btnFetch = New-Object System.Windows.Forms.Button
$btnFetch.Text = 'Fetch packages'
$btnFetch.Location = New-Object System.Drawing.Point(12, 112)
$btnFetch.Size = New-Object System.Drawing.Size(130, 28)
$form.Controls.Add($btnFetch)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = 'Install'
$btnInstall.Location = New-Object System.Drawing.Point(150, 112)
$btnInstall.Size = New-Object System.Drawing.Size(110, 28)
$form.Controls.Add($btnInstall)

$btnDoctor = New-Object System.Windows.Forms.Button
$btnDoctor.Text = 'Doctor'
$btnDoctor.Location = New-Object System.Drawing.Point(268, 112)
$btnDoctor.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnDoctor)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = 'Uninstall'
$btnUninstall.Location = New-Object System.Drawing.Point(376, 112)
$btnUninstall.Size = New-Object System.Drawing.Size(110, 28)
$form.Controls.Add($btnUninstall)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Status: Ready'
$lblStatus.Location = New-Object System.Drawing.Point(500, 118)
$lblStatus.Size = New-Object System.Drawing.Size(190, 18)
$lblStatus.Anchor = 'Top,Right'
$lblStatusBase = New-Object System.Drawing.Font('Segoe UI', 9)
$lblStatus.Font = New-Object System.Drawing.Font($lblStatusBase, 'Bold')
$lblStatus.TextAlign = 'MiddleRight'
$form.Controls.Add($lblStatus)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(12, 150)
$txtLog.Size = New-Object System.Drawing.Size(678, 320)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = 'White'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($txtLog)

function Add-Log { param([string]$Text) $txtLog.AppendText($Text + "`r`n") }

function Set-Status {
    param([string]$S)
    $lblStatus.Text = "Status: $S"
    $lblStatus.ForeColor = switch ($S) {
        'Installed' { 'ForestGreen' }
        'Failed'    { 'Firebrick' }
        'Missing exe' { 'DarkOrange' }
        default     { 'Black' }
    }
}

function Update-StatusFromPaths {
    $p = $txtExe.Text.Trim().Trim('"')
    if (-not $p) {
        $lblExePath.Text = ''; $lblGameDir.Text = ''
        Set-Status 'Ready'
        return
    }
    if ((Test-Path $p -PathType Container) -or ($p -notmatch '(?i)\.exe$') -or (-not (Test-Path $p -PathType Leaf))) {
        $lblExePath.Text = "exe:  $p"
        $lblGameDir.Text = ''
        Set-Status 'Missing exe'
        return
    }
    $game = Split-Path -Parent $p
    $lblExePath.Text = "exe:   $p"
    $lblGameDir.Text = "game:  $game"
    if (Test-Path (Join-Path $game '.z2e-state.json') -PathType Leaf) { Set-Status 'Installed' }
    else { Set-Status 'Ready' }
}

function Invoke-GuiAction {
    param([string[]]$CliArgs, [string]$FailStatus = 'Failed')
    $buttons = @($btnFetch, $btnInstall, $btnDoctor, $btnUninstall)
    foreach ($b in $buttons) { $b.Enabled = $false }
    try {
        Add-Log ('> pwsh z2e-fsr41.ps1 ' + ($CliArgs -join ' '))
        $res = Invoke-Z2EAction -CliArgs $CliArgs
        if ($res.Text) { Add-Log $res.Text }
        Add-Log ("exit code: $($res.Code)")
        Add-Log ''
        return $res
    }
    finally {
        foreach ($b in $buttons) { $b.Enabled = $true }
    }
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Game executable (*.exe)|*.exe|All files (*.*)|*.*'
    $dlg.Title = 'Select game EXE'
    $last = Read-Z2EGuiConfig
    if ($last -and $last.lastExe -and (Test-Path (Split-Path -Parent $last.lastExe))) {
        $dlg.InitialDirectory = Split-Path -Parent $last.lastExe
        $dlg.FileName = Split-Path -Leaf $last.lastExe
    }
    if ($dlg.ShowDialog($form) -eq 'OK') {
        $txtExe.Text = $dlg.FileName
        try { Write-Z2EGuiConfig -LastExe $dlg.FileName } catch { }
    }
})

$txtExe.Add_TextChanged({ Update-StatusFromPaths })

$btnFetch.Add_Click({
    $res = Invoke-GuiAction -CliArgs @('fetch')
    if ($res.Text -match '7-Zip required') {
        Add-Log 'NOTE: install 7-Zip (7z on PATH), then Fetch again.'
        [System.Windows.Forms.MessageBox]::Show('7-Zip required: install 7-Zip and add 7z to PATH, then Fetch again.',
            'Z2E FSR 4.1 Box', 'OK', 'Warning') | Out-Null
        Set-Status 'Failed'
        return
    }
    if ($res.Text -match '(?i)7-?zip') {
        Add-Log 'NOTE: OptiScaler releases are .7z — install 7-Zip and make sure 7z is on PATH.'
    }
    Update-StatusFromPaths
})

$btnInstall.Add_Click({
    try {
        $r = Resolve-Z2EGamePaths -ExePath $txtExe.Text
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Z2E FSR 4.1 Box',
            'OK', 'Warning') | Out-Null
        Set-Status 'Missing exe'
        return
    }
    $res = Invoke-GuiAction -CliArgs @(
        'install', '--game', $r.game, '--exe', $r.exe,
        '--fsr', $cmbFsr.Text, '--inject', $cmbInject.Text
    )
    if ($res.Code -eq 0) {
        Update-StatusFromPaths
        [System.Windows.Forms.MessageBox]::Show(
            "In-game: Insert → FSR 3.X/4 → FFX 4.1.1`n`nWatermark must read FSR4-i8. FSR3 means the force failed.",
            'Installed', 'OK', 'Information') | Out-Null
    }
    elseif ($res.Text -match '7-Zip required') {
        [System.Windows.Forms.MessageBox]::Show('7-Zip required: install 7-Zip and add 7z to PATH, then Fetch again.',
            'Z2E FSR 4.1 Box', 'OK', 'Warning') | Out-Null
        Set-Status 'Failed'
    }
    elseif ($res.Text -match '--i-understand-anticheat') {
        [System.Windows.Forms.MessageBox]::Show($res.Text, 'Anticheat detected',
            'OK', 'Warning') | Out-Null
        Set-Status 'Failed'
    }
    else { Set-Status 'Failed' }
})

$btnDoctor.Add_Click({
    try { $r = Resolve-Z2EGamePaths -ExePath $txtExe.Text }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Z2E FSR 4.1 Box',
            'OK', 'Warning') | Out-Null
        Set-Status 'Missing exe'; return
    }
    $res = Invoke-GuiAction -CliArgs @('doctor', '--game', $r.game)
    if ($res.Code -eq 0) { Update-StatusFromPaths } else { Set-Status 'Failed' }
})

$btnUninstall.Add_Click({
    try { $r = Resolve-Z2EGamePaths -ExePath $txtExe.Text }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Z2E FSR 4.1 Box',
            'OK', 'Warning') | Out-Null
        Set-Status 'Missing exe'; return
    }
    $res = Invoke-GuiAction -CliArgs @('uninstall', '--game', $r.game)
    if ($res.Code -eq 0) { Update-StatusFromPaths } else { Set-Status 'Failed' }
})

# Восстановить последний EXE
$cfg = Read-Z2EGuiConfig
if ($cfg -and $cfg.lastExe -and (Test-Path $cfg.lastExe -PathType Leaf)) {
    $txtExe.Text = $cfg.lastExe
}
Update-StatusFromPaths

if ($Smoke) {
    Write-Host 'smoke: form built OK'
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
