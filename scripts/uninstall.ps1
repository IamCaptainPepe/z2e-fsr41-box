# z2e-fsr41-box: удаление установки. Трогаем ТОЛЬКО файлы из .z2e-state.json
# и восстановленные бэкапы. Сейвы игры не трогаем.

function Invoke-Z2EUninstall {
    param([string]$Game)
    if (-not $Game) { throw 'Нужен --game "D:\Games\Foo"' }
    $Game = (Resolve-Path $Game).Path
    $statePath = Join-Path $Game '.z2e-state.json'
    if (-not (Test-Path $statePath -PathType Leaf)) {
        throw "Нет .z2e-state.json в $Game — установка z2e-fsr41 не найдена, ничего не делаю."
    }
    $s = Get-Content -Raw $statePath | ConvertFrom-Json

    # 1) Удаляем только то, что положили мы
    foreach ($f in @($s.copied)) {
        $p = Join-Path $Game $f
        if (Test-Path $p -PathType Leaf) {
            Remove-Item $p -Force
            Write-Host "удалён: $f"
        }
    }

    # 2) Восстанавливаем бэкапы
    $backupDir = Join-Path $Game '.z2e-backup'
    foreach ($f in @($s.backups)) {
        $b = Join-Path $backupDir $f
        if (Test-Path $b -PathType Leaf) {
            Copy-Item $b (Join-Path $Game $f) -Force
            Write-Host "восстановлен из бэкапа: $f"
        }
    }

    # 3) Убираем своё состояние/бэкапы → папка как до install
    Remove-Item -Recurse -Force $backupDir -ErrorAction SilentlyContinue
    Remove-Item -Force $statePath
    Write-Host '[ok] Удалено. Сейвы игры не тронуты.'
}
