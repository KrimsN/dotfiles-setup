# modules/extras.sh

tldr и fastfetch.

## Миграция на диспетчер (2026-08-25)

Модуль переведён на общий диспетчер `pkg::install` — см.
[scripts/lib/pkg-registry.sh](../../scripts/lib/pkg-registry.sh) и
[docs/design/pkg-metadata-json.md](../design/pkg-metadata-json.md).
`extras::install` теперь сводится к `pkg::install tldr` и
`pkg::install fastfetch` — способ установки, приоритет и все нюансы
(EPEL для tldr на CentOS/RHEL, musl-ловушка fastfetch) описаны
декларативно в [data/packages/registry.json](../../data/packages/registry.json),
не в этом файле. Требует `scripts/lib/pkg-registry.sh` вместо
`epel.sh`/`github-release.sh` напрямую.

**Нюанс с fastfetch** (зафиксирован в `registry.json`, для истории): у
него в GitHub Releases есть ассет `fastfetch-musl-amd64.tar.gz`, но
вопреки названию он не статический — реально слинкован с musl libc
динамически (`NEEDED libc.musl-x86_64.so.1`), и на glibc-дистрибутивах
(все наши целевые) не запускается ("required file not found", нет
musl-рантайма). Использован обычный `fastfetch-linux-<arch>.tar.gz`
(glibc-сборка) вместо него — работает везде. В отличие от eza/delta/zoxide,
где musl-ассеты — честный статик (там всё ок).

## Тестирование

**До миграции** (актуально для старой реализации — прямых вызовов
`os::pkg_install`/`github_release::install` в этом файле, полностью
заменённых на `pkg::install`): end-to-end (установка + идемпотентность)
на Ubuntu 24.04, Fedora (актуальная), CentOS Stream 9 (подтверждена ветка
EPEL для tldr).

**После миграции:** проверено юнит-тестами диспетчера, интеграционным
тестом на заглушках, и end-to-end через `.claude/skills/test-module/` на
Ubuntu 24.04, Debian 12, Fedora, CentOS Stream 9 (в связке
`base,cli-tools,extras,python-tools`, два прогона на идемпотентность) —
везде чисто. На CentOS 9 отдельно подтверждена ветка EPEL для tldr.

## `EXTRAS_PACKAGES` (2026-08-25)

Список пакетов модуля переехал из тела `extras::install` (два подряд
`pkg::install`) в константу `EXTRAS_PACKAGES` — так же, как это уже
было устроено в `cli-tools.sh` (`CLI_PACKAGES`) и `diagnostics.sh`
(`DIAGNOSTICS_PACKAGES`).

Причина — второй потребитель списка: `knrc uninstall`
([uninstall.md](uninstall.md)) подключает модуль ради этой константы,
чтобы знать, что именно он принёс на машину. Своя копия списка внутри
`uninstall.sh` рано или поздно разъехалась бы с этой, а цена расхождения
— пакет, который не попал ни в удаление, ни даже в отчёт «осталось».
