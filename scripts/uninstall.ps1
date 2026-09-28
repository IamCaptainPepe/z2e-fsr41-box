# z2e-fsr41-box: удаление установки. Трогаем ТОЛЬКО файлы из .z2e-state.json
# и восстановленные бэкапы. Сейвы игры не трогаем.

function Find-Z2EStateDir {
    # Ищем папку установки: сначала <path>\.z2e-state.json, иначе глубина 3
    # (state лежит рядом с exe, а --game может быть корнём Steam).
    param([string]$Path)
    if (Test-Path (Join-Path $Path '.z2e-state.json') -PathType Leaf) { return $Path }
    $hit = Get-ChildItem -Path $Path -Filter '.z2e-state.json' -File -Force -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.z2e-backup[\\/]' } | Select-Object -First 1
    if ($hit) { return $hit.Directory.FullName }
    return $null
}

function Invoke-Z2EUninstall {
    param([string]$Game)
    if (-not $Game) { throw 'Нужен --game "D:\Games\Foo"' }
    $Game = (Resolve-Path $Game).Path
    $dir = Find-Z2EStateDir -Path $Game
    if (-not $dir) {
        throw "Нет .z2e-state.json в $Game (и на глубине 3) — установка z2e-fsr41 не найдена, ничего не делаю."
    }
    if ($dir -ne $Game) { Write-Host "state найден рядом с exe: $dir" }
    $statePath = Join-Path $dir '.z2e-state.json'
    $s = Get-Content -Raw $statePath | ConvertFrom-Json

    # 1) Удаляем только то, что положили мы
    foreach ($f in @($s.copied)) {
        $p = Join-Path $dir $f
        if (Test-Path $p -PathType Leaf) {
            Remove-Item $p -Force
            Write-Host "удалён: $f"
        }
    }
    # 1b) Папки (Agility SDK: D3D12_OptiScaler и пр.)
    if ($s.copiedDirs) {
        foreach ($d in @($s.copiedDirs)) {
            $p = Join-Path $dir $d
            if (Test-Path $p -PathType Container) {
                Remove-Item -Recurse -Force $p
                Write-Host "удалена папка: $d\"
            }
        }
    }

    # 2) Восстанавливаем бэкапы
    $backupDir = Join-Path $dir '.z2e-backup'
    foreach ($f in @($s.backups)) {
        $b = Join-Path $backupDir $f
        if (Test-Path $b -PathType Leaf) {
            Copy-Item $b (Join-Path $dir $f) -Force
            Write-Host "восстановлен из бэкапа: $f"
        }
    }

    # 3) Убираем своё состояние/бэкапы → папка как до install
    Remove-Item -Recurse -Force $backupDir -ErrorAction SilentlyContinue
    Remove-Item -Force $statePath
    Write-Host "[ok] Удалено из $dir. Сейвы игры не тронуты."
}
