# z2e-fsr41-box: загрузка релизов OptiScaler + FSR 4.1 INT8 по versions.json.
# Основной путь — GitHub Releases API (не парсинг HTML). При 403 — fallback_url.
# Z2E_FAKE_PAYLOAD=1 — генерация фейковых архивов для тестов (CI без сети).

function Get-Z2ECacheDir {
    # Windows: %LOCALAPPDATA%; вне Windows (CI/тесты): XDG cache
    if ($env:LOCALAPPDATA) { $base = $env:LOCALAPPDATA }
    elseif ($env:XDG_CACHE_HOME) { $base = $env:XDG_CACHE_HOME }
    else { $base = Join-Path $HOME '.cache' }
    Join-Path $base 'z2e-fsr41/cache'
}

function Get-Z2EVersions {
    param([string]$RepoRoot)
    Get-Content -Raw (Join-Path $RepoRoot 'versions.json') | ConvertFrom-Json
}

function Get-Z2EManifestPath {
    Join-Path (Get-Z2ECacheDir) 'manifest.json'
}

function Get-Z2ESha256 {
    param([string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function New-Z2EFakeZip {
    # Упаковать набор файлов (имя -> текст|byte[]) в zip для фейк-режима
    param([string]$ZipPath, [hashtable]$Files)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('z2efake-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    foreach ($name in $Files.Keys) {
        $content = $Files[$name]
        $dest = Join-Path $tmp $name
        if ($content -is [byte[]]) { [System.IO.File]::WriteAllBytes($dest, $content) }
        else { Set-Content -Path $dest -Value $content -Encoding UTF8 }
    }
    Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $ZipPath -Force
    Remove-Item -Recurse -Force $tmp
}

function New-Z2EFakeCache {
    param([string]$RepoRoot, [string]$Fsr)
    $cache = Get-Z2ECacheDir
    $osZip  = Join-Path $cache 'optiscaler-fake.zip'
    $fsrZip = Join-Path $cache 'fsr-int8-fake.zip'

    # Типичный OptiScaler.ini релиза (секция [FSR] как в master 2026-09,
    # БЕЗ Fsr4ForceEnableInt8 — чтобы тестировать правило «только если есть»).
    $fakeIni = @'
[General]
Scale=0
Overlay=true

[DX12]
OptiScalerDllPath=

[FSR]
; фейк-ini для тестов (структура как у релиза v0.9.4)
Fsr4ForceModel=0
Fsr4EnableWatermark=false
Fsr4DoNotLoadAmdxc64=false
Fsr4Preset=auto
Fsr4Update=false
'@
    $peHeader = [byte[]](0x4D,0x5A) + [byte[]](0..61)   # «MZ…» — заглушка dll
    New-Z2EFakeZip -ZipPath $osZip -Files @{
        'OptiScaler.dll'                    = $peHeader
        'amd_fidelityfx_dx12.dll'           = $peHeader
        'amd_fidelityfx_upscaler_dx12.dll'  = $peHeader
        'OptiScaler.ini'                    = $fakeIni
    }
    New-Z2EFakeZip -ZipPath $fsrZip -Files @{
        'amd_fidelityfx_upscaler_dx12.dll' = ([byte[]](0x4D,0x5A) + [byte[]](100..163))
    }

    $manifest = [ordered]@{
        fake       = $true
        generated  = (Get-Date).ToString('o')
        optiscaler = [ordered]@{ tag = 'v0.9.4-fake'; file = (Split-Path $osZip -Leaf); url = 'fake://local'; size = (Get-Item $osZip).Length; sha256 = (Get-Z2ESha256 $osZip) }
        fsr_int8   = [ordered]@{ version = $Fsr; file = (Split-Path $fsrZip -Leaf); url = 'fake://local'; size = (Get-Item $fsrZip).Length; sha256 = (Get-Z2ESha256 $fsrZip) }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Get-Z2EManifestPath) -Encoding UTF8
    Write-Host "[fake] Готово: $osZip, $fsrZip + manifest.json (Z2E_FAKE_PAYLOAD=1)"
}

function Invoke-Z2EDownload {
    # Скачивание ассета; при 403/ошибке API — fallback_url из versions.json
    param([string]$Url, [string]$OutFile, [hashtable]$Headers, [string]$FallbackUrl)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $Headers
        return
    } catch {
        if ($FallbackUrl) {
            Write-Warning "Прямая загрузка не удалась ($_), пробую fallback: $FallbackUrl"
            Invoke-WebRequest -Uri $FallbackUrl -OutFile $OutFile -Headers $Headers
            return
        }
        throw
    }
}

function Invoke-Z2EFetch {
    param(
        [string]$RepoRoot,
        [string]$Channel = 'stable',
        [string]$Fsr = '4.1.1b'
    )
    $cache = Get-Z2ECacheDir
    New-Item -ItemType Directory -Force -Path $cache | Out-Null

    if ($env:Z2E_FAKE_PAYLOAD -eq '1') {
        New-Z2EFakeCache -RepoRoot $RepoRoot -Fsr $Fsr
        return
    }

    $v = Get-Z2EVersions -RepoRoot $RepoRoot
    $headers = @{ 'User-Agent' = $v.user_agent; 'Accept' = 'application/vnd.github+json' }

    function Get-GH { param([string]$Uri) Invoke-RestMethod -Uri $Uri -Headers $headers }

    # --- OptiScaler ---
    if ($Channel -eq 'nightly') { $osCfg = $v.optiscaler.nightly } else { $osCfg = $v.optiscaler.stable }
    $osTag = $osCfg.tag
    Write-Host "OptiScaler: $osCfg.repo @ $osTag"
    $rel = Get-GH "https://api.github.com/repos/$($osCfg.repo)/releases/tags/$osTag"
    $contains = @($osCfg.asset_contains)
    $asset = $rel.assets | Where-Object {
        $n = $_.name
        (@($contains | Where-Object { $n -like "*$_*" })).Count -eq $contains.Count
    } | Select-Object -First 1
    if (-not $asset) { throw "В релизе $osTag нет ассета, подходящего под asset_contains: $($contains -join ', ')" }
    $osFile = Join-Path $cache $asset.name
    Invoke-Z2EDownload -Url $asset.browser_download_url -OutFile $osFile -Headers $headers -FallbackUrl $osCfg.fallback_url
    Write-Host "[ok] $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB)"

    # --- FSR 4 INT8 ---
    $fsrCfg = $v.fsr_int8.$Fsr
    if (-not $fsrCfg) { throw "Версия FSR '$Fsr' не описана в versions.json" }
    Write-Host "FSR INT8: $($fsrCfg.repo) ~ '$($fsrCfg.release_name_contains)'"
    $rels = Get-GH "https://api.github.com/repos/$($fsrCfg.repo)/releases"
    $cand = @($rels | Where-Object { $_.name -like "*$($fsrCfg.release_name_contains)*" })
    $best = $null
    if ($fsrCfg.prefer) { $best = @($cand | Where-Object { $_.name -like "*$($fsrCfg.prefer)*" }) | Select-Object -First 1 }
    if (-not $best) { $best = $cand | Select-Object -First 1 }
    if (-not $best) { throw "Релиз FSR INT8 '$Fsr' не найден (зеркала: $($v.mirrors.fsr_int8 -join ' '))" }
    $asset2 = @($best.assets | Where-Object { $_.name -like '*.zip' -or $_.name -like '*.7z' }) | Select-Object -First 1
    if (-not $asset2) { throw "В релизе '$($best.name)' нет zip/7z ассетов" }
    $fsrFile = Join-Path $cache $asset2.name
    Invoke-Z2EDownload -Url $asset2.browser_download_url -OutFile $fsrFile -Headers $headers -FallbackUrl $fsrCfg.fallback_url
    Write-Host "[ok] $($asset2.name)"

    # --- manifest (реальные filename + size + sha256) ---
    $manifest = [ordered]@{
        fake       = $false
        generated  = (Get-Date).ToString('o')
        optiscaler = [ordered]@{ tag = $osTag; file = $asset.name; url = $asset.browser_download_url; size = (Get-Item $osFile).Length; sha256 = (Get-Z2ESha256 $osFile) }
        fsr_int8   = [ordered]@{ version = $Fsr; release = $best.name; file = $asset2.name; url = $asset2.browser_download_url; size = (Get-Item $fsrFile).Length; sha256 = (Get-Z2ESha256 $fsrFile) }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Get-Z2EManifestPath) -Encoding UTF8
    Write-Host "[ok] manifest: $(Get-Z2EManifestPath)"
}
