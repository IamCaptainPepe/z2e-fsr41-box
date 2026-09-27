# z2e-fsr41-box: бережный мерж ключей профиля Z2E в OptiScaler.ini.
# Правила (см. profiles/z2e-fsr41.ini):
#  - upsert ТОЛЬКО ключей профиля внутри существующих секций;
#  - Fsr4ForceModel / Fsr4ForceEnableInt8 / Fsr4Update — ставим только если
#    ключ УЖЕ есть в ini релиза (алиасы: новый Fsr4ForceModel=2, старый Fsr4ForceEnableInt8=true);
#  - Fsr4Update никогда не ставим в true; если ключа нет — не добавляем;
#  - Fsr4EnableWatermark / Fsr4DoNotLoadAmdxc64 — upsert всегда;
#  - если секции [FSR] нет — создаём её в конце файла;
#  - комментарии и чужие ключи сохраняем.

function Read-Z2EProfile {
    # Парсим профиль: ordered section -> ordered key/value (комментарии отбрасываем)
    param([string]$ProfilePath)
    $res = [ordered]@{}
    $sec = $null
    foreach ($line in (Get-Content $ProfilePath)) {
        if ($line -match '^\s*[;#]' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*\[(.+?)\]') {
            $sec = $Matches[1]
            if (-not $res.Contains($sec)) { $res[$sec] = [ordered]@{} }
            continue
        }
        if (-not $sec) { continue }
        $t = ($line -split ';', 2)[0].Trim()
        if ($t -match '^([A-Za-z0-9_]+)\s*=\s*(.+)$') {
            $res[$sec][$Matches[1]] = $Matches[2].Trim()
        }
    }
    $res
}

function Find-Z2ESectionRange {
    # Возвращает @(startIdx, endIdx) строки секции [name] или $null
    param([string[]]$Lines, [string]$Section)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*\[(.+?)\]') {
            if ($Matches[1] -eq $Section) { $start = $i }
            elseif ($start -ge 0) { return @($start, ($i - 1)) }
        }
    }
    if ($start -ge 0) { return @($start, ($Lines.Count - 1)) }
    return $null
}

function Merge-Z2EIni {
    # Мержит профиль в целевой ini. Возвращает список записанных ключей "Sec/Key=Value".
    param(
        [string]$TargetPath,
        [string]$ProfilePath
    )
    $profile = Read-Z2EProfile -ProfilePath $ProfilePath
    $lines = [System.Collections.Generic.List[string]](Get-Content $TargetPath)
    $written = @()

    # Ключи, которые ставим ТОЛЬКО если они уже есть в ini релиза (алиасы форса INT8 / update)
    $onlyIfPresent = @{
        'Fsr4ForceModel'      = '2'
        'Fsr4ForceEnableInt8' = 'true'
        'Fsr4Update'          = 'false'   # никогда true
    }
    # Ключи, которые никогда НЕ добавляем, если их нет (только правим существующие)
    $neverAdd = @{ 'Fsr4Update' = $true }

    foreach ($sec in $profile.Keys) {
        $r = Find-Z2ESectionRange -Lines $lines.ToArray() -Section $sec
        if ($null -eq $r) {
            # Секции нет — создаём в конце файла и кладём профильные ключи
            # (кроме neverAdd: их в несуществующей секции выдумывать нельзя).
            $lines.Add('') | Out-Null
            $lines.Add("[$sec]") | Out-Null
            foreach ($k in $profile[$sec].Keys) {
                if ($neverAdd.ContainsKey($k)) { continue }
                $v = $profile[$sec][$k]
                $lines.Add("$k=$v") | Out-Null
                $written += "$sec/$k=$v"
            }
            continue
        }
        foreach ($k in $profile[$sec].Keys) {
            $v = $profile[$sec][$k]
            $r = Find-Z2ESectionRange -Lines $lines.ToArray() -Section $sec
            $foundIdx = -1
            for ($i = $r[0] + 1; $i -le $r[1]; $i++) {
                if ($lines[$i] -match ('^\s*' + [regex]::Escape($k) + '\s*=')) { $foundIdx = $i; break }
            }
            if ($foundIdx -lt 0) {
                if ($onlyIfPresent.ContainsKey($k) -or $neverAdd.ContainsKey($k)) { continue }
                # вставим в конец секции (после последней непустой строки)
                $ins = $r[1] + 1
                while (($ins - 1) -gt $r[0] -and $lines[$ins - 1].Trim() -eq '') { $ins-- }
                $lines.Insert($ins, "$k=$v")
                $written += "$sec/$k=$v"
                continue
            }
            if ($lines[$foundIdx] -match '^\s*[A-Za-z0-9_]+\s*=\s*(.*?)\s*$' -and $Matches[1] -eq $v) { continue }
            $lines[$foundIdx] = "$k=$v"
            $written += "$sec/$k=$v"
        }
    }

    Set-Content -Path $TargetPath -Value $lines -Encoding UTF8
    $written
}
