# z2e-fsr41-box

*EN: Thin PowerShell 7 installer-wrapper for running **FSR 4.1 INT8** (via OptiScaler) on
Ryzen **Z2 Extreme** handhelds (Radeon 890M, RDNA 3.5, gfx1150): ROG Xbox Ally X, MSI Claw A8
BZ2EM and similar. It downloads other people's releases, installs them next to the game exe,
writes the Z2E profile, supports backup/uninstall/doctor. No AMD/FSR/OptiScaler binaries in
this repo. Windows only in v1.*

## Для кого

Владельцы ROG Xbox Ally X / MSI Claw A8 (Z2E, iGPU Radeon 890M, RDNA 3.5 / gfx1150), которые
хотят картинку FSR 4 в играх с DLSS/FSR-апскейлом.

**Это НЕ форк OptiScaler и НЕ копия OptiScaler Client.** Только обёртка-установщик:
скачивает чужие релизы, ставит в папку игры, пишет профиль Z2E, умеет backup/uninstall/doctor.

## Чего нет (и не будет в v1)

- AMD/FSR/OptiScaler DLL в репозитории — их тут нет и не будет (см. NOTICE.md).
- GUI — не делаем. При желании профиль `profiles/z2e-fsr41.ini` можно импортировать в
  [OptiScaler Client](https://github.com/Optiscaler-Client/Optiscaler-Client).
- Linux-установщика — «потом», см. в конце.
- Мультиплеера с античитом — **нельзя** (см. SECURITY.md).

## Суть (без магии)

Официально FSR 4.1.1 **INT8** — это RDNA 3 desktop (RX 7000), FP8 — RDNA 4.
RDNA 3.5 iGPU (Z2E / 890M) AMD не открыла: нативного драйверного FSR 4 на Ally X **нет**.

Обход: **OptiScaler + INT8 DLL + форс модели 2** (`Fsr4ForceModel=2`, старый алиас —
`Fsr4ForceEnableInt8=true`). Если форс не сработал — у OptiScaler внутренний fallback в FSR3.

Проверка **только ватермарком** в игре (Insert → выбор апскейлера):

| Ватермарк | Вердикт |
|---|---|
| `FSR4-i8` / `4.1.1` | ✅ ок |
| `FSR3` | ❌ провал форса (fallback) |

На RDNA 3.5 **НЕ ставьте `Fsr4Update=true`** — частый автооткат в FSR3. Профиль это учитывает:
если ключа нет в ini релиза — мы его не добавляем, если есть — ставим `false`.

## Ожидания на Z2E

Картинка заметно лучше FSR 3.1 (меньше шлейфов, стабильнее края).
**FPS часто падает на 10–20%** — INT8 на iGPU дешёвый не бывает. Это компромисс качества,
а не «бесплатный апгрейд».

## Установка

Нужен PowerShell 7 (`pwsh`).

```powershell
git clone https://github.com/IamCaptainPepe/z2e-fsr41-box.git
cd z2e-fsr41-box

# 1. Скачать релизы (GitHub Releases API, кэш в %LOCALAPPDATA%\z2e-fsr41\cache)
pwsh ./tools/z2e-fsr41.ps1 fetch

# 2. Поставить в игру
pwsh ./tools/z2e-fsr41.ps1 install --game "D:\Games\Foo"
# опции: --exe path\to\game.exe  --channel stable|nightly  --fsr 4.1.1b|4.1.1|4.0.2c
#         --inject dxgi|winmm|version  --dry-run  --i-understand-anticheat

# 3. Проверить
pwsh ./tools/z2e-fsr41.ps1 doctor --game "D:\Games\Foo"

# 4. Снять
pwsh ./tools/z2e-fsr41.ps1 uninstall --game "D:\Games\Foo"
```

Канал по умолчанию: OptiScaler **v0.9.4** + FSR **4.1.1b INT8** (fallback 4.1.1 → 4.0.2c),
всё запиннено в `versions.json`.

- `install` без `--exe` сам ищет самый крупный exe в корне игры (отбрасывая
  launcher/crash/unitycrash/easyanticheat). Неясно — требует `--exe`. Вслепую в корень
  UE5/Phoenix-игр не ставит.
- Существующие `dxgi.dll`, `winmm.dll`, `version.dll`, `amd_fidelityfx*.dll`,
  `OptiScaler.ini`, `OptiScaler.dll` бэкапятся в `<game>\.z2e-backup\`.
- Состояние (что скопировано/бэкапнуто, какие ключи ini записаны) — `<game>\.z2e-state.json`.
  `uninstall` удаляет **только** файлы из state и возвращает бэкапы. Сейвы не трогает.
- Имена upscaler-dll берутся из распакованного архива, а не хардкодом.

## Ключи INI и алиасы

Профиль: `profiles/z2e-fsr41.ini`, мержит `scripts/IniMerge.ps1` (комментарии и чужие ключи
сохраняет; секцию `[FSR]` при отсутствии создаёт в конце файла).

| Ключ | Значение | Правило |
|---|---|---|
| `Fsr4ForceModel` | `2` | 0 = no override, 1 = FP8, **2 = INT8**. Ставится, только если ключ есть в ini релиза |
| `Fsr4ForceEnableInt8` | `true` | Старый алиас (notes v0.9.4). Только если ключ есть в ini релиза |
| оба ключа | — | Ставятся оба |
| `Fsr4Update` | `false` | Если ключ есть — `false`; если нет — **не добавляем**. `true` на RDNA 3.5 запрещено |
| `Fsr4EnableWatermark` | `true` | Всегда |
| `Fsr4DoNotLoadAmdxc64` | `true` | Всегда |
| FP8 (`Fsr4ForceModel=1`) | — | На Z2E **никогда** |

Ключи **сверяются с OptiScaler.ini из распакованного релиза**, а не по памяти — правила выше
реализованы в `IniMerge` как «only if present».

## Тесты / CI

Без сети и без реальных dll:

```powershell
$env:Z2E_FAKE_PAYLOAD = '1'
pwsh ./tools/z2e-fsr41.ps1 fetch
pwsh ./tools/z2e-fsr41.ps1 install --game testdata/fake-game --dry-run
pwsh ./tools/z2e-fsr41.ps1 install --game testdata/fake-game
pwsh ./tools/z2e-fsr41.ps1 doctor --game testdata/fake-game   # exit 0
pwsh ./tools/z2e-fsr41.ps1 uninstall --game testdata/fake-game
```

Fake-режим генерирует в кэш zip'ы с фейковым OptiScaler (ini с типичной секцией `[FSR]`,
пустые dll) и фейковый INT8-архив. CI (`.github/workflows/ci.yml`) на windows-latest:
парсинг всех `.ps1`, fake install→doctor→uninstall, проверка «в репозитории нет ни одного .dll».

## Credits

- [OptiScaler](https://github.com/optiscaler/OptiScaler) (+ [nightly](https://github.com/optiscaler/OptiScaler-nightly/releases),
  [wiki](https://github.com/optiscaler/OptiScaler/wiki),
  [Installation](https://github.com/optiscaler/OptiScaler/wiki/Installation),
  [Manual](https://github.com/optiscaler/OptiScaler/wiki/Manual-Installation),
  [FSR4 compatibility list](https://github.com/optiscaler/OptiScaler/wiki/fsr4-compatibility-list),
  [OptiScaler.ini в master](https://raw.githubusercontent.com/optiscaler/OptiScaler/master/OptiScaler.ini),
  [OptiPatcher](https://github.com/optiscaler/OptiPatcher))
- [Nukem dlssg-to-fsr3](https://github.com/Nukem9/dlssg-to-fsr3) (уже в бандле OptiScaler 0.9+)
- FSR 4 INT8 зеркала: [Agustinm28/OptiScaler-Extras](https://github.com/Agustinm28/OptiScaler-Extras/releases),
  [daniel-h-0/bc250-fsr4-fork](https://github.com/daniel-h-0/bc250-fsr4-fork/releases),
  [benjamimgois (fsr-int8-411b)](https://github.com/benjamimgois/OptiScaler-builds/releases/tag/fsr-int8-411b),
  [007Lore/AMD-FSR-4-INT8](https://github.com/007Lore/AMD-FSR-4-INT8/releases)
- GUI-вдохновение (код не копировали): [Optiscaler-Client](https://github.com/Optiscaler-Client/Optiscaler-Client)
- Гайд для Ally: [rogallylife.com](https://rogallylife.com/2025/10/14/optiscaler-fsr-4-rog-xbox-ally-x/)

## Disclaimer

Только одиночные/офлайн-игры. Античиты (EAC/BattlEye/Vanguard) детектируют подмену рендер-стека —
`install` блокирует известные онлайн-тайтлы без флага `--i-understand-anticheat`.
См. [SECURITY.md](SECURITY.md). Ответственность за бан/сломанную игру — на вас.

## v2 идеи (не реализуем в v1)

- GUI — **не делать**; для GUI-сценариев есть OptiScaler Client, профиль совместим.
- Linux: [Decky Framegen](https://github.com/xXJSONDeruloXx/Decky-Framegen) / [decky.xyz](https://decky.xyz/)
  + тот же `Fsr4ForceModel=2`.
