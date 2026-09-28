# z2e-fsr41-box: Windows GUI (WinForms) поверх CLI tools/z2e-fsr41.ps1.
# Двойной клик: tools/Z2E-FSR41-Box.cmd. Терминал не нужен.
#   По умолчанию — handheld-раскладка (1280x800, крупные кнопки под палец/стик).
#   -Compact    — старый компактный layout 720x520 (Z2E_COMPACT=1 из .cmd)
#   -Smoke      — собрать форму и выйти (CI: форма строится)
#   -SelfTest   — fetch→install→doctor→uninstall на testdata/fake-game
#                с Z2E_FAKE_PAYLOAD=1 без окна (работает и на Linux pwsh)
param(
    [switch]$Compact,
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

function Test-Z2ECacheReady {
    # fetch уже выполнялся? (manifest в кэше — тот же путь, что у fetch.ps1)
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA }
            elseif ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME }
            else { Join-Path $HOME '.cache' }
    Test-Path (Join-Path $base 'z2e-fsr41/cache/manifest.json') -PathType Leaf
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

# ---- геометрия: handheld (по умолчанию) / compact --------------------------
if ($Compact) {
    $W = 720;  $H = 520;  $MinW = 640; $MinH = 460
    $FLabel = 9.0; $FBtn = 9.0; $FStatus = 9.0; $FLog = 9.0
    $HBrowse = 25; $HInstall = 28; $HSecond = 28; $HPath = 23; $PathLines = 1
    $M = 12
} else {
    $W = 1280; $H = 800;  $MinW = 800; $MinH = 600
    $FLabel = 12.0; $FBtn = 14.0; $FStatus = 18.0; $FLog = 11.0
    $HBrowse = 64; $HInstall = 72; $HSecond = 64; $HPath = 64; $PathLines = 2
    $M = 24
}
$FLabelB = New-Object System.Drawing.Font('Segoe UI', $FLabel)
$FBtnF   = New-Object System.Drawing.Font('Segoe UI', $FBtn)
$FStatusF = New-Object System.Drawing.Font('Segoe UI', ([math]::Max($FStatus, 9)),
    ([System.Drawing.FontStyle]::Bold))
$FLogF   = New-Object System.Drawing.Font('Consolas', $FLog)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Z2E FSR 4.1 Box'
$form.Size = New-Object System.Drawing.Size($W, $H)
$form.MinimumSize = New-Object System.Drawing.Size($MinW, $MinH)
$form.StartPosition = 'CenterScreen'
$form.Font = $FLabelB

function New-Lbl {
    param([string]$Text, [int]$X, [int]$Y, [int]$W2 = 0, [string]$Color = 'Black')
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    if ($W2 -gt 0) { $l.Size = New-Object System.Drawing.Size($W2, 24); $l.AutoSize = $false }
    else { $l.AutoSize = $true }
    if ($Color -ne 'Black') { $l.ForeColor = $Color }
    $form.Controls.Add($l)
    $l
}

function New-Btn {
    param([string]$Text, [int]$X, [int]$Y, [int]$W2, [int]$H2)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W2, $H2)
    $b.Font = $FBtnF
    $form.Controls.Add($b)
    $b
}

$cw = $form.ClientSize.Width - 2 * $M   # рабочая ширина (с якорями растёт)

# 1) Label "Game EXE"
[void](New-Lbl 'Game EXE' $M $M)

# 2) Read-only path box (wrap) + huge Browse
$browseW = [math]::Max(150, [int]($cw * 0.22))
$txtExe = New-Object System.Windows.Forms.TextBox
$txtExe.Location = New-Object System.Drawing.Point($M, ($M + 30))
$txtExe.Size = New-Object System.Drawing.Size(($cw - $browseW - 8), $HPath)
$txtExe.Multiline = ($PathLines -gt 1)
$txtExe.WordWrap = $true
$txtExe.ReadOnly = $true
$txtExe.Font = $FLabelB
$txtExe.Anchor = 'Top,Left,Right'
$txtExe.TabStop = $false
$txtExe.BackColor = 'White'
$form.Controls.Add($txtExe)

$btnBrowse = New-Btn 'Browse…' ($M + $cw - $browseW) ($M + 30) $browseW $HBrowse
$btnBrowse.Anchor = 'Top,Right'

# 3) exe: / game:
$lblExePath = New-Lbl '' $M ($M + 30 + $HPath + 6) $cw 'DimGray'
$lblExePath.Anchor = 'Top,Left,Right'
$lblGameDir = New-Lbl '' $M ($M + 30 + $HPath + 30) $cw 'DimGray'
$lblGameDir.Anchor = 'Top,Left,Right'

# 4) Primary Install (full width)
$yInstall = $M + 30 + $HPath + 58
$btnInstall = New-Btn 'Install' $M $yInstall $cw $HInstall
$btnInstall.Anchor = 'Top,Left,Right'

# 5) Secondary row: Remove | Check
$ySecond = $yInstall + $HInstall + 12
$half = [int](($cw - 12) / 2)
$btnUninstall = New-Btn 'Remove' $M $ySecond $half $HSecond
$btnUninstall.Anchor = 'Top,Left,Right'
$btnDoctor = New-Btn 'Check' ($M + $half + 12) $ySecond $half $HSecond
$btnDoctor.Anchor = 'Top,Left,Right'
if ($Compact) {
    # в компакте рядом становится и Fetch (старый layout имел 4 кнопки)
    $btnFetch = New-Btn 'Fetch' ($M + 2 * ($half + 12)) $ySecond ([math]::Max(90, $cw - 2 * ($half + 12))) $HSecond
    $btnFetch.Anchor = 'Top,Right'
}

# 6) Status big and colored
$yStatus = $ySecond + $HSecond + 12
$lblStatus = New-Lbl 'Status: Ready' $M $yStatus $cw 'Black'
$lblStatus.Font = $FStatusF
$lblStatus.Anchor = 'Top,Left,Right'

# Advanced (collapsed by default)
$yAdv = $yStatus + 44
$chkAdv = New-Object System.Windows.Forms.CheckBox
$chkAdv.Text = 'Advanced'
$chkAdv.Location = New-Object System.Drawing.Point($M, $yAdv)
$chkAdv.AutoSize = $true
$chkAdv.Font = $FLabelB
$form.Controls.Add($chkAdv)

$yPanel = $yAdv + 34
$advPanel = New-Object System.Windows.Forms.Panel
$advPanel.Location = New-Object System.Drawing.Point($M, $yPanel)
$advPanel.Size = New-Object System.Drawing.Size($cw, 56)
$advPanel.Visible = $false
$advPanel.Anchor = 'Top,Left,Right'
$form.Controls.Add($advPanel)

$l1 = New-Object System.Windows.Forms.Label
$l1.Text = 'FSR version'; $l1.AutoSize = $true; $l1.Location = New-Object System.Drawing.Point(0, 8)
$advPanel.Controls.Add($l1)
$cmbFsr = New-Object System.Windows.Forms.ComboBox
$cmbFsr.Location = New-Object System.Drawing.Point(0, 30)
$cmbFsr.Size = New-Object System.Drawing.Size(140, 24)
$cmbFsr.DropDownStyle = 'DropDownList'
[void]$cmbFsr.Items.AddRange(@('4.1.1b', '4.1.1', '4.0.2c'))
$cmbFsr.SelectedIndex = 0
$advPanel.Controls.Add($cmbFsr)
$l2 = New-Object System.Windows.Forms.Label
$l2.Text = 'Inject'; $l2.AutoSize = $true; $l2.Location = New-Object System.Drawing.Point(160, 8)
$advPanel.Controls.Add($l2)
$cmbInject = New-Object System.Windows.Forms.ComboBox
$cmbInject.Location = New-Object System.Drawing.Point(160, 30)
$cmbInject.Size = New-Object System.Drawing.Size(140, 24)
$cmbInject.DropDownStyle = 'DropDownList'
[void]$cmbInject.Items.AddRange(@('dxgi', 'winmm', 'version'))
$cmbInject.SelectedIndex = 0
$advPanel.Controls.Add($cmbInject)

# 7) Log: last 8 lines, readable
$LogLines = 8
$lineH = [int]($FLogF.Height * 1.35) + 2
$yLog = $yPanel + 12
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point($M, $yLog)
$txtLog.Size = New-Object System.Drawing.Size($cw, ($lineH * ($LogLines + 1)) + 8)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = 'White'
$txtLog.Font = $FLogF
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($txtLog)

$script:logBuf = [System.Collections.Generic.List[string]]::new()
function Add-Log {
    param([string]$Text)
    foreach ($ln in ('' + $Text) -split "`r?`n") {
        if ($ln.Trim().Length) { $script:logBuf.Add($ln) }
    }
    $tail = $script:logBuf | Select-Object -Last $LogLines
    $txtLog.Text = ($tail -join "`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Set-Status {
    param([string]$S)
    $lblStatus.Text = "Status: $S"
    $lblStatus.ForeColor = switch ($S) {
        'Installed'     { 'ForestGreen' }
        'Failed'        { 'Firebrick' }
        'Missing exe'   { 'DarkOrange' }
        'Downloading…'  { 'DarkSlateBlue' }
        'Installing…'   { 'DarkSlateBlue' }
        default         { 'Black' }
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
    # state лежит рядом с exe (возможна вложенность bin\x64) — ищем до глубины 3
    $state = @(Get-ChildItem -Path $game -Filter '.z2e-state.json' -File -Force -Recurse -Depth 3 -ErrorAction SilentlyContinue)
    if ($state.Count) { Set-Status 'Installed' } else { Set-Status 'Ready' }
}

function Show-7ZipWarning {
    Add-Log 'NOTE: install 7-Zip (7z on PATH), then try again.'
    [System.Windows.Forms.MessageBox]::Show('7-Zip required: install 7-Zip and add 7z to PATH, then Fetch again.',
        'Z2E FSR 4.1 Box', 'OK', 'Warning') | Out-Null
    Set-Status 'Failed'
}

function Get-AllButtons {
    if ($Compact) { @($btnBrowse, $btnInstall, $btnUninstall, $btnDoctor, $btnFetch) }
    else          { @($btnBrowse, $btnInstall, $btnUninstall, $btnDoctor) }
}

function Invoke-GuiAction {
    param([string[]]$CliArgs)
    $buttons = Get-AllButtons
    foreach ($b in $buttons) { $b.Enabled = $false }
    try {
        Add-Log ('> pwsh z2e-fsr41.ps1 ' + ($CliArgs -join ' '))
        $res = Invoke-Z2EAction -CliArgs $CliArgs
        if ($res.Text) { Add-Log $res.Text }
        Add-Log ("exit code: $($res.Code)")
        return $res
    }
    finally {
        foreach ($b in $buttons) { $b.Enabled = $true }
    }
}

$chkAdv.Add_CheckedChanged({
    $advPanel.Visible = [bool]$chkAdv.Checked
    # лог прижимаем под панель (панель видима — сдвигаем вниз)
    $newY = if ($advPanel.Visible) { $yPanel + 60 } else { $yPanel + 12 }
    $txtLog.Height += ($txtLog.Location.Y - $newY)
    $txtLog.Location = New-Object System.Drawing.Point($M, $newY)
})

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Game executable (*.exe)|*.exe'
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

if ($Compact) {
    $btnFetch.Add_Click({
        $res = Invoke-GuiAction -CliArgs @('fetch')
        if ($res.Text -match '7-Zip required') { Show-7ZipWarning; return }
        if ($res.Text -match '(?i)7-?zip') {
            Add-Log 'NOTE: OptiScaler releases are .7z — install 7-Zip and make sure 7z is on PATH.'
        }
        Update-StatusFromPaths
    })
}

$btnInstall.Add_Click({
    try {
        $r = Resolve-Z2EGamePaths -ExePath $txtExe.Text
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Z2E FSR 4.1 Box',
            'OK', 'Warning') | Out-Null
        Set-Status 'Missing exe'
        return
    }
    # Пустой кэш → сначала fetch (одна кнопка на всё)
    if (-not (Test-Z2ECacheReady)) {
        Set-Status 'Downloading…'
        Add-Log 'Downloading…'
        $f = Invoke-GuiAction -CliArgs @('fetch')
        if ($f.Text -match '7-Zip required') { Show-7ZipWarning; return }
        if ($f.Code -ne 0) { Set-Status 'Failed'; return }
    }
    Set-Status 'Installing…'
    Add-Log 'Installing…'
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
    elseif ($res.Text -match '7-Zip required') { Show-7ZipWarning }
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
    Write-Host "smoke: form built OK (compact=$([bool]$Compact))"
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
