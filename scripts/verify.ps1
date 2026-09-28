# z2e-fsr41-box: doctor — проверка, что установка на месте и ключи Z2E не съехали.
# Возвращает 0 при успехе (exit code), 1 при любой проблеме.

function Get-Z2EFsrSection {
    # Хэштег-безопасный парсинг секции [FSR]: key(lower) -> value
    param([string]$IniPath)
    $vals = @{}
    $inFsr = $false
    foreach ($line in (Get-Content $IniPath)) {
        if ($line -match '^\s*\[(.+?)\]') { $inFsr = ($Matches[1] -eq 'FSR'); continue }
        if ($inFsr -and $line -notmatch '^\s*[;#]' -and $line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*(?:;.*)?$') {
            $vals[$Matches[1].ToLower()] = $Matches[2].ToLower()
        }
    }
    $vals
}

function Invoke-Z2EDoctor {
    param([string]$Game)
    if (-not $Game) { Write-Host '[fail] Нужен --game'; return 1 }
    $Game = (Resolve-Path $Game).Path
    # state рядом с exe: сначала <path>, иначе глубина 3 (Find-Z2EStateDir в uninstall.ps1)
    $dir = Find-Z2EStateDir -Path $Game
    if (-not $dir) {
        Write-Host '[fail] .z2e-state.json нет (ни в папке, ни на глубине 3) — эта игра не устанавливалась через z2e-fsr41'
        return 1
    }
    if ($dir -ne $Game) { Write-Host "state найден рядом с exe: $dir" }
    $Game = $dir
    $statePath = Join-Path $Game '.z2e-state.json'
    $s = Get-Content -Raw $statePath | ConvertFrom-Json
    $fail = @()

    # 1) INI + ключи профиля (с учётом алиасов)
    $iniPath = Join-Path $Game 'OptiScaler.ini'
    if (-not (Test-Path $iniPath -PathType Leaf)) {
        $fail += 'OptiScaler.ini отсутствует'
    }
    else {
        $v = Get-Z2EFsrSection -IniPath $iniPath
        $modelOk = ($v['fsr4forcemodel'] -eq '2')
        $int8Ok  = ($v['fsr4forceenableint8'] -eq 'true')
        if (-not ($modelOk -or $int8Ok)) {
            $fail += 'нет форса INT8: нужен Fsr4ForceModel=2 и/или Fsr4ForceEnableInt8=true (алиасы)'
        }
        if ($v['fsr4enablewatermark'] -ne 'true') { $fail += 'Fsr4EnableWatermark не true — нечем проверить FSR4-i8' }
        if ($v['fsr4update'] -eq 'true') { $fail += 'Fsr4Update=true — на RDNA 3.5 вызывает автооткат в FSR3' }
        if ($v['fsr4donotloadamdxc64'] -ne 'true') { $fail += 'Fsr4DoNotLoadAmdxc64 не true' }
    }

    # 2) Inject dll и INT8 upscaler
    $injectDll = Join-Path $Game ($s.inject + '.dll')
    if (-not (Test-Path $injectDll -PathType Leaf)) { $fail += "нет $($s.inject).dll (inject)" }
    if (-not (Test-Path (Join-Path $Game $s.upscaler) -PathType Leaf)) { $fail += "нет INT8 upscaler: $($s.upscaler)" }
    foreach ($f in @($s.copied)) {
        if (-not (Test-Path (Join-Path $Game $f) -PathType Leaf)) { $fail += "отсутствует установленный файл: $f" }
    }

    if ($fail.Count -gt 0) {
        foreach ($f in $fail) { Write-Host "[fail] $f" }
        return 1
    }
    Write-Host '[ok] OptiScaler + INT8 + ключи Z2E на месте.'
    Write-Host 'В игре Insert → FSR 3.X/4 → FFX 4.1.1, ватермарк должен быть FSR4-i8.'
    Write-Host 'Ватермарк FSR3 = форс не сработал (внутренний fallback), см. README.'
    return 0
}
