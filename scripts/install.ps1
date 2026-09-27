# z2e-fsr41-box: установка OptiScaler + FSR 4.1 INT8 в папку игры.
# Логика — как Manual Installation в wiki OptiScaler, но неинтерактивно.

function Expand-Z2EArchive {
    param([string]$Archive, [string]$Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    if ($Archive -like '*.zip') {
        Expand-Archive -Path $Archive -DestinationPath $Dest -Force
        return
    }
    # Релизы OptiScaler — .7z; нужен 7-Zip на машине
    $seven = Get-Command 7z, 7za, 7zr -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $seven) {
        throw "Для распаковки '$Archive' нужен 7-Zip (7z в PATH). В тестах используй Z2E_FAKE_PAYLOAD=1 (zip)."
    }
    & $seven.Source x $Archive "-o$Dest" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z завершился с кодом $LASTEXITCODE" }
}

function Find-Z2EExe {
    # Целевой exe: --exe, иначе самый крупный exe в корне игры
    # (исключая launcher/crash/unitycrash/easyanticheat и пр.).
    param([string]$Game, [string]$Exe)
    if ($Exe) {
        if (-not (Test-Path $Exe -PathType Leaf)) { throw "--exe не найден: $Exe" }
        return Get-Item $Exe
    }
    $bad = 'launcher|crash|setup|unins|easyanticheat|battleye|updater|redist|dxsetup|vgc'
    $exes = @(Get-ChildItem -Path $Game -Filter *.exe -File | Where-Object { $_.Name -notmatch $bad })
    if ($exes.Count -eq 0) { throw "В корне игры нет подходящего .exe — укажи --exe (вслепую в UE5/Phoenix не ставим)." }
    $top = @($exes | Sort-Object Length -Descending)
    if ($top.Count -gt 1 -and $top[0].Length -eq $top[1].Length) {
        throw "Несколько exe одинакового размера ($($top[0].Name), $($top[1].Name) …) — укажи --exe."
    }
    $top[0]
}

function Test-Z2EAnticheat {
    # Возвращает строку-объяснение, если игра/папка похожа на онлайн с античитом.
    param([string]$Game)
    $names = 'destiny', 'valorant', 'rainbow six', 'fortnite', 'apex', 'pubg', 'tarkov', 'the finals'
    $p = $Game.ToLower()
    foreach ($n in $names) {
        if ($p -like "*$n*") { return "имя папки игры совпадает с онлайн-тайтлом: $n" }
    }
    foreach ($d in 'EasyAntiCheat', 'BattlEye', 'Vanguard') {
        $hit = Get-ChildItem -Path $Game -Directory -Recurse -Depth 2 -Filter "*$d*" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return "в папке игры найдена подпапка античита: $($hit.FullName)" }
    }
    return $null
}

function Invoke-Z2EInstall {
    param(
        [string]$RepoRoot,
        [string]$Game,
        [string]$Exe,
        [string]$Channel = 'stable',
        [string]$Fsr = '4.1.1b',
        [string]$Inject = 'dxgi',
        [bool]$DryRun = $false,
        [bool]$AckAnticheat = $false
    )
    if (-not $Game) { throw 'Нужен --game "D:\Games\Foo"' }
    $Game = (Resolve-Path $Game).Path
    if ($Inject -notin 'dxgi', 'winmm', 'version') { throw "--inject принимает dxgi|winmm|version" }

    # 0) Античит
    $ac = Test-Z2EAnticheat -Game $Game
    if ($ac) {
        if (-not $AckAnticheat) {
            throw "Обнаружен античит ($ac). OptiScaler подменяет рендер-стек — риск бана в мультиплеере. Если игра одиночная и ты осознаёшь риск, добавь --i-understand-anticheat."
        }
        Write-Warning "Античит: $ac — продолжаю по --i-understand-anticheat, на свой страх."
    }

    # 1) Целевой exe
    $exeItem = Find-Z2EExe -Game $Game -Exe $Exe
    Write-Host "Целевой exe: $($exeItem.FullName)"

    # 2) Кэш
    $cache = Get-Z2ECacheDir
    $manifestPath = Get-Z2EManifestPath
    $needFetch = -not (Test-Path $manifestPath)
    if (-not $needFetch) {
        $m = Get-Content -Raw $manifestPath | ConvertFrom-Json
        foreach ($f in $m.optiscaler.file, $m.fsr_int8.file) {
            if (-not (Test-Path (Join-Path $cache $f))) { $needFetch = $true }
        }
    }
    if ($needFetch) { Invoke-Z2EFetch -RepoRoot $RepoRoot -Channel $Channel -Fsr $Fsr }
    $m = Get-Content -Raw $manifestPath | ConvertFrom-Json
    $osZip  = Join-Path $cache $m.optiscaler.file
    $fsrZip = Join-Path $cache $m.fsr_int8.file

    $injectDllName = "$Inject.dll"
    if ($DryRun) {
        Write-Host '--- DRY RUN, ничего не меняю ---'
        Write-Host "game:     $Game"
        Write-Host "exe:      $($exeItem.Name)"
        Write-Host "inject:   $injectDllName (копия OptiScaler.dll)"
        Write-Host "optiscaler: $($m.optiscaler.file) ($($m.optiscaler.tag))"
        Write-Host "fsr int8: $($m.fsr_int8.file) ($($m.fsr_int8.version))"
        Write-Host "ini:      OptiScaler.ini <- мерж profiles/z2e-fsr41.ini"
        return
    }

    # 3) Распаковка во временную папку
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('z2e-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Z2EArchive -Archive $osZip  -Dest (Join-Path $tmp 'os')
        Expand-Z2EArchive -Archive $fsrZip -Dest (Join-Path $tmp 'fsr')

        $osDll = Get-ChildItem (Join-Path $tmp 'os') -Recurse -Filter 'OptiScaler.dll' | Select-Object -First 1
        if (-not $osDll) { throw 'В архиве OptiScaler не найден OptiScaler.dll' }
        $osIniSrc = Get-ChildItem (Join-Path $tmp 'os') -Recurse -Filter 'OptiScaler.ini' | Select-Object -First 1
        $osUp = @(Get-ChildItem (Join-Path $tmp 'os') -Recurse -Filter 'amd_fidelityfx_upscaler*.dll')
        $fsrUp = Get-ChildItem (Join-Path $tmp 'fsr') -Recurse -Filter 'amd_fidelityfx_upscaler*.dll' | Select-Object -First 1
        if (-not $fsrUp) { throw 'В архиве FSR INT8 не найден upscaler-диалект (amd_fidelityfx_upscaler*.dll)' }
        # Имя upscaler берём из распакованного архива, не хардкодим
        $upName = if ($osUp.Count -ge 1) { $osUp[0].Name } else { $fsrUp.Name }

        # 4) Бэкап существующих файлов
        $backupDir = Join-Path $Game '.z2e-backup'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $watch = @($injectDllName, 'OptiScaler.dll', 'OptiScaler.ini', 'dxgi.dll', 'winmm.dll', 'version.dll', 'amd_fidelityfx_dx12.dll', 'amd_fidelityfx_upscaler_dx12.dll') | Select-Object -Unique
        $backups = @()
        foreach ($t in $watch) {
            $src = Join-Path $Game $t
            if (Test-Path $src -PathType Leaf) {
                Copy-Item $src (Join-Path $backupDir $t) -Force
                $backups += $t
            }
        }

        # 5) Копирование payload рядом с exe (Manual Installation)
        $copied = @()
        Copy-Item $osDll.FullName (Join-Path $Game 'OptiScaler.dll') -Force; $copied += 'OptiScaler.dll'
        Copy-Item (Join-Path $Game 'OptiScaler.dll') (Join-Path $Game $injectDllName) -Force; $copied += $injectDllName
        foreach ($d in (Get-ChildItem (Join-Path $tmp 'os') -Recurse -Filter 'amd_fidelityfx_*.dll')) {
            Copy-Item $d.FullName (Join-Path $Game $d.Name) -Force
            if ($d.Name -notin $copied) { $copied += $d.Name }
        }

        # 6) INT8 upscaler: заменяем одноимённый файл бандла реальным INT8-файлом
        Copy-Item $fsrUp.FullName (Join-Path $Game $upName) -Force
        if ($upName -notin $copied) { $copied += $upName }
        Write-Host "INT8 upscaler: $upName <- $($fsrUp.Name) (из архива Extras)"

        # 7) INI: берём ini релиза, мержим профиль Z2E
        $iniPath = Join-Path $Game 'OptiScaler.ini'
        if (-not (Test-Path $iniPath)) {
            if (-not $osIniSrc) { throw 'Ни в игре, ни в архиве нет OptiScaler.ini для мержа' }
            Copy-Item $osIniSrc.FullName $iniPath
            if ('OptiScaler.ini' -notin $backups) { $copied += 'OptiScaler.ini' }
        }
        $keys = @(Merge-Z2EIni -TargetPath $iniPath -ProfilePath (Join-Path $RepoRoot 'profiles/z2e-fsr41.ini'))
        foreach ($k in $keys) { Write-Host "ini: $k" }

        # 8) Состояние
        $state = [ordered]@{
            installed = (Get-Date).ToString('o')
            channel   = $Channel
            fsr       = $Fsr
            inject    = $Inject
            exe       = $exeItem.FullName
            copied    = $copied
            backups   = $backups
            upscaler  = $upName
            iniKeys   = $keys
        }
        $state | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $Game '.z2e-state.json') -Encoding UTF8

        Write-Host "[ok] Установлено в $Game (inject=$injectDllName, FSR INT8=$Fsr)"
        Write-Host 'Проверка в игре: Insert → выбрать FSR 4 → ватермарк должен быть FSR4-i8 / 4.1.1.'
        Write-Host 'FSR3 в ватермарке = форс не сработал (fallback). Подробности: README.'
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}
