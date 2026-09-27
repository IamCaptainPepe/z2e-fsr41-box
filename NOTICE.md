# NOTICE

Этот репозиторий содержит **только обёртку-установщик** (PowerShell-скрипты, профиль ini,
документацию). В git намеренно не хранятся чужие бинарники.

Скачиваются при `fetch` и принадлежат своим авторам:

| Компонент | Источник | Лицензия автора |
|---|---|---|
| OptiScaler (dll, ini, бандл) | https://github.com/optiscaler/OptiScaler | MIT (см. релиз) |
| OptiScaler nightly | https://github.com/optiscaler/OptiScaler-nightly/releases | как в релизе |
| Nukem dlssg-to-fsr3 (в бандле OptiScaler) | https://github.com/Nukem9/dlssg-to-fsr3 | см. репозиторий автора |
| FSR 4.1 INT8 DLL (upscaler) | https://github.com/Agustinm28/OptiScaler-Extras/releases и зеркала из versions.json | проприетарные/серые сборки AMD FSR — см. страницу релиза |
| AMD FSR SDK (упоминания) | AMD | лицензия AMD |

`fetch` пишет `cache/manifest.json` с фактическими url/filename/size/sha256 — кэш не коммитится.

MIT-лицензия этого репозитория распространяется **только** на скрипты-обёртку.
