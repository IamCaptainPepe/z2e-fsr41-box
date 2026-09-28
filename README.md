# Z2E FSR 4.1 Box

A thin **PowerShell 7 installer-wrapper** that runs **FSR 4.1 INT8** (via
[OptiScaler](https://github.com/optiscaler/OptiScaler)) on Ryzen **Z2 Extreme**
handhelds (iGPU Radeon 890M, RDNA 3.5 / gfx1150): ROG Xbox Ally X, MSI Claw A8
BZ2EM and similar. It downloads other people's releases, installs them next to
the game exe, writes the Z2E profile, and supports backup / uninstall / doctor.
**No AMD / FSR / OptiScaler binaries are bundled in this repo.** Windows only in v1.*

## What this is / is not

- **Is**: a GUI + CLI installer. You pick a game `.exe`, click Install, get FSR 4
  watermarks in-game.
- **Is not**: a fork of OptiScaler, a copy of OptiScaler Client, a mod loader,
  a Steam/Epic/Xbox library scanner. No library detection, no Avalonia, no Electron.
  The engine scripts (`scripts/*.ps1`, `tools/z2e-fsr41.ps1`) are the real tool;
  the GUI is a WinForms shell on top of them.

## Why a wrapper exists (no official FSR 4 on Z2E)

Officially, FSR 4.1.1 **INT8** is RDNA 3 desktop (RX 7000) and FP8 is RDNA 4.
AMD has **not** enabled the RDNA 3.5 iGPU (Z2 Extreme / Radeon 890M / gfx1150):
there is **no native driver-side FSR 4** on the Ally X.

The workaround: **OptiScaler + INT8 DLL + force model 2** (`Fsr4ForceModel=2`,
old alias `Fsr4ForceEnableInt8=true`). If the force fails, OptiScaler silently
falls back to FSR 3. On RDNA 3.5 **never set `Fsr4Update=true`** — it is a known
cause of automatic fallback to FSR 3. The bundled profile respects this: keys are
written only where they exist in the release ini (see the INI table below).

## Run the GUI (no terminal)

Requires **PowerShell 7** (`pwsh`) installed. Double-click:

```
tools\Z2E-FSR41-Box.cmd
```

1. **Browse…** → select the **game `.exe` file** (not a folder). The window shows
   the resolved `exe:` and `game:` paths under the box. The last exe is remembered
   in `%LOCALAPPDATA%\z2e-fsr41\gui.json`.
2. Pick **FSR version** (4.1.1b / 4.1.1 / 4.0.2c, default 4.1.1b) and
   **Inject** (dxgi / winmm / version, default dxgi).
3. **Fetch packages** (first time) → downloads OptiScaler + FSR INT8 releases.
4. **Install** → done. Status shows `Installed` while `<game>\.z2e-state.json` exists.
5. **Doctor** re-checks files and INI keys; **Uninstall** removes exactly what the
   installer copied and restores backups.

The GUI never passes `--i-understand-anticheat`. If the target looks like an
online game with anti-cheat, a MessageBox blocks the install.

### Verify in-game (watermark)

Press **Insert** in-game → select the upscaler → read the watermark:

| Watermark | Verdict |
|---|---|
| `FSR4-i8` / `4.1.1` | ✅ working |
| `FSR3` | ❌ force failed (internal fallback) |

### Expectations on Z2E

Image quality is clearly better than FSR 3.1 (less ghosting, steadier edges).
**FPS often drops 10–20%** — INT8 on an iGPU is not free. This is a quality
trade, not a free upgrade.

### 7-Zip

OptiScaler releases are `.7z`. Install **7-Zip** and keep `7z` (or `7za`/`7zr`)
on `PATH` — required for real `.7z` downloads. `.zip` assets need nothing extra.
Tests (`Z2E_FAKE_PAYLOAD=1`) use zip only.

If Fetch/Install fails with "archive empty", the `.7z` unwrapped into a nested
wrapper folder — the installer now locates `OptiScaler.dll` recursively and
flattens from the directory that contains it (Agility SDK subfolder
`D3D12_OptiScaler` is copied too).

The canonical FSR INT8 extras repo is
[Optiscaler-Client/Optiscaler-Extras](https://github.com/Optiscaler-Client/Optiscaler-Extras)
(pinned in `versions.json`; direct `.7z` fallback URLs, not HTML pages).

## Anticheat warning

Single-player / offline games only. Anti-cheats (EAC / BattlEye / Vanguard)
detect render-stack injection — `install` blocks known online titles unless you
pass `--i-understand-anticheat` (CLI only; the GUI refuses). See
[SECURITY.md](SECURITY.md). Ban / broken-game responsibility is yours.

## CLI (still fully supported)

```powershell
git clone https://github.com/IamCaptainPepe/z2e-fsr41-box.git
cd z2e-fsr41-box

pwsh ./tools/z2e-fsr41.ps1 fetch
pwsh ./tools/z2e-fsr41.ps1 install --game "D:\Games\Foo"
# options: --exe path\to\game.exe  --channel stable|nightly  --fsr 4.1.1b|4.1.1|4.0.2c
#          --inject dxgi|winmm|version  --dry-run  --i-understand-anticheat
pwsh ./tools/z2e-fsr41.ps1 doctor --game "D:\Games\Foo"
pwsh ./tools/z2e-fsr41.ps1 uninstall --game "D:\Games\Foo"
```

Default channel: OptiScaler **v0.9.4** + FSR **4.1.1b INT8** (fallback 4.1.1 → 4.0.2c),
pinned in `versions.json`.

- `install` without `--exe` picks the largest exe in the game root (skipping
  launcher/crash/setup/easyanticheat…), falling back to a depth-3 search
  (`bin/x64`, `Win64`); ties require `--exe`.
- Existing `dxgi.dll`, `winmm.dll`, `version.dll`, `amd_fidelityfx*.dll`,
  `OptiScaler.ini` are backed up to `<game>\.z2e-backup\`.
- State (what was copied/backed up, which ini keys were written) lives in
  `<game>\.z2e-state.json`. `uninstall` removes **only** files from state and
  restores backups. Saves are untouched.
- The installer copies the **whole OptiScaler bundle** and renames `OptiScaler.dll`
  into a **single** proxy (`dxgi.dll` / `winmm.dll` / `version.dll`), per the
  OptiScaler Manual Installation wiki. The INT8 upscaler replaces the bundle's
  upscaler dll, keeping the canonical name from the INT8 archive.

## INI keys and aliases

Profile: `profiles/z2e-fsr41.ini`, merged by `scripts/IniMerge.ps1` (comments and
foreign keys preserved; `[FSR]` section appended if missing).

| Key | Value | Rule |
|---|---|---|
| `Fsr4ForceModel` | `2` | 0 = no override, 1 = FP8, **2 = INT8**. Only if the key exists in the release ini |
| `Fsr4ForceEnableInt8` | `true` | Old alias (v0.9.4 notes). Only if the key exists in the release ini |
| both keys | — | Both are set when both exist |
| `Fsr4Update` | `false` | If present → `false`; if absent → **not added**. `true` is forbidden on RDNA 3.5 |
| `Fsr4EnableWatermark` | `true` | Always |
| `Fsr4DoNotLoadAmdxc64` | `true` | Always |
| FP8 (`Fsr4ForceModel=1`) | — | **Never** on Z2E |

Keys are validated against the unpacked `OptiScaler.ini` of the release, not from
memory — the rules above are implemented in `IniMerge` as "only if present".

## Tests / CI

Headless, offline, no real dlls:

```powershell
$env:Z2E_FAKE_PAYLOAD = '1'
pwsh ./tools/z2e-fsr41.ps1 fetch
pwsh ./tools/z2e-fsr41.ps1 install --game testdata/fake-game --dry-run
pwsh ./tools/z2e-fsr41.ps1 install --game testdata/fake-game
pwsh ./tools/z2e-fsr41.ps1 doctor --game testdata/fake-game   # exit 0
pwsh ./tools/z2e-fsr41.ps1 uninstall --game testdata/fake-game
```

GUI selftest (same cycle through the GUI's action layer, no window, runs on Linux too):

```powershell
pwsh ./tools/z2e-gui.ps1 -SelfTest
pwsh ./tools/z2e-gui.ps1 -Smoke   # Windows: builds the WinForms form and exits
```

CI (`.github/workflows/ci.yml`) on windows-latest: parses every `.ps1`, runs the
fake install→doctor→uninstall cycle, runs the GUI selftest and form smoke test,
and asserts **no `.dll` is committed**.

## Credits

- [OptiScaler](https://github.com/optiscaler/OptiScaler) (+ [nightly](https://github.com/optiscaler/OptiScaler-nightly/releases),
  [wiki](https://github.com/optiscaler/OptiScaler/wiki),
  [Installation](https://github.com/optiscaler/OptiScaler/wiki/Installation),
  [Manual](https://github.com/optiscaler/OptiScaler/wiki/Manual-Installation),
  [FSR4 compatibility list](https://github.com/optiscaler/OptiScaler/wiki/fsr4-compatibility-list),
  [OptiScaler.ini in master](https://raw.githubusercontent.com/optiscaler/OptiScaler/master/OptiScaler.ini),
  [OptiPatcher](https://github.com/optiscaler/OptiPatcher))
- [Nukem dlssg-to-fsr3](https://github.com/Nukem9/dlssg-to-fsr3) (already bundled in OptiScaler 0.9+)
- FSR 4 INT8 mirrors: [Agustinm28/OptiScaler-Extras](https://github.com/Agustinm28/OptiScaler-Extras/releases),
  [daniel-h-0/bc250-fsr4-fork](https://github.com/daniel-h-0/bc250-fsr4-fork/releases),
  [benjamimgois (fsr-int8-411b)](https://github.com/benjamimgois/OptiScaler-builds/releases/tag/fsr-int8-411b),
  [007Lore/AMD-FSR-4-INT8](https://github.com/007Lore/AMD-FSR-4-INT8/releases)
- GUI inspiration (no code copied): [Optiscaler-Client](https://github.com/Optiscaler-Client/Optiscaler-Client)
- Ally guide: [rogallylife.com](https://rogallylife.com/2025-10-14/optiscaler-fsr-4-rog-xbox-ally-x/)

## Disclaimer

Single-player / offline games only. Anti-cheats detect render-stack injection.
See [SECURITY.md](SECURITY.md).

## v2 ideas (not in v1)

- GUI: keep WinForms; for richer GUI scenarios use OptiScaler Client — the
  profile format is compatible.
- Linux: [Decky Framegen](https://github.com/xXJSONDeruloXx/Decky-Framegen) / [decky.xyz](https://decky.xyz/)
  + the same `Fsr4ForceModel=2`.
