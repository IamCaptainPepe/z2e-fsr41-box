#!/usr/bin/env pwsh
# z2e-fsr41-box — тонкая CLI-обёртка установки FSR 4.1 INT8 (OptiScaler)
# для handheld с Ryzen Z2 Extreme (Radeon 890M, RDNA 3.5, gfx1150).
# PowerShell 7. Windows — целевая платформа; Linux/macOS pwsh — только тесты.
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot '../scripts/fetch.ps1')
. (Join-Path $PSScriptRoot '../scripts/IniMerge.ps1')
. (Join-Path $PSScriptRoot '../scripts/install.ps1')
. (Join-Path $PSScriptRoot '../scripts/uninstall.ps1')
. (Join-Path $PSScriptRoot '../scripts/verify.ps1')

function Show-Usage {
    @'
z2e-fsr41-box — FSR 4.1 INT8 (OptiScaler) для Ryzen Z2 Extreme (Ally X / Claw A8)

Использование:
  pwsh ./tools/z2e-fsr41.ps1 fetch
  pwsh ./tools/z2e-fsr41.ps1 install --game "D:\Games\Foo" [--exe path]
        [--channel stable|nightly] [--fsr 4.1.1b|4.1.1|4.0.2c]
        [--inject dxgi|winmm|version] [--dry-run] [--i-understand-anticheat]
  pwsh ./tools/z2e-fsr41.ps1 uninstall --game "..."
  pwsh ./tools/z2e-fsr41.ps1 doctor --game "..."

Кэш загрузок: %LOCALAPPDATA%\z2e-fsr41\cache
Состояние игры: <game>\.z2e-state.json   Бэкапы: <game>\.z2e-backup\
Тесты без сети: $env:Z2E_FAKE_PAYLOAD=1 (см. README).
'@ | Write-Host
}

# Разбор аргументов вида --key value / --flag
$h = @{}
for ($i = 0; $i -lt $Rest.Count; $i++) {
    $a = $Rest[$i]
    if ($a -in '--game', '--exe', '--channel', '--fsr', '--inject') {
        if (($i + 1) -ge $Rest.Count) { throw "Нужно значение для $a" }
        $h[$a.Substring(2)] = $Rest[$i + 1]; $i++
    }
    elseif ($a -in '--dry-run', '--i-understand-anticheat') { $h[$a.Substring(2)] = $true }
    elseif ($a -in '-h', '--help') { Show-Usage; exit 0 }
    else { throw "Неизвестный аргумент: $a (см. --help)" }
}
if (-not $h['channel']) { $h['channel'] = 'stable' }
if (-not $h['fsr'])     { $h['fsr'] = '4.1.1b' }
if (-not $h['inject'])  { $h['inject'] = 'dxgi' }

switch ($Command) {
    'fetch' {
        Invoke-Z2EFetch -RepoRoot $RepoRoot -Channel $h['channel'] -Fsr $h['fsr']
    }
    'install' {
        Invoke-Z2EInstall -RepoRoot $RepoRoot -Game $h['game'] -Exe $h['exe'] `
            -Channel $h['channel'] -Fsr $h['fsr'] -Inject $h['inject'] `
            -DryRun ([bool]$h['dry-run']) -AckAnticheat ([bool]$h['i-understand-anticheat'])
    }
    'uninstall' {
        Invoke-Z2EUninstall -Game $h['game']
    }
    'doctor' {
        exit (Invoke-Z2EDoctor -Game $h['game'])
    }
    default {
        Show-Usage
        exit 1
    }
}
