# modules/diagnostics.sh

Диагностические утилиты: rsync, dig, ncdu, lsof, mtr — через общий
диспетчер `pkg::install` (реестр `data/packages/registry.json` +
`data/packages/methods/pkg.json`). Добавлены по согласованию с
пользователем (2026-08-25) — базовый список программ в
[CLAUDE.md](../../CLAUDE.md) не покрывал сетевую/файловую диагностику.

Вынесены в отдельный модуль, а не добавлены в `modules/base.sh`: у dig
и mtr имя пакета расходится между apt и dnf/yum, а `modules/base.sh`
ставит весь список одним вызовом `os::pkg_install` с одинаковыми
именами — это ровно та задача, для которой существует декларативный
реестр пакетов, а не место для веток по `PKG_MANAGER` внутри модуля.

Требует `scripts/lib/pkg-registry.sh` (и, транзитивно,
`scripts/lib/epel.sh` — для ncdu на CentOS/RHEL).

## Расхождения имён пакетов между дистрибутивами

- **dig** — бинарник входит в пакет `dnsutils` на apt (Debian/Ubuntu),
  `bind-utils` на dnf/yum (Fedora/CentOS). В базовых репах везде,
  `bind-utils` есть в AppStream CentOS Stream 9 — EPEL не требуется.
- **mtr** — на apt пакет `mtr` — метапакет, тянущий GTK/X11-зависимости
  (`libgtk2.0-0` и т.п.) ради GUI-версии; берём `mtr-tiny` (тот же
  бинарник `/usr/bin/mtr`, без GUI-зависимостей). На dnf/yum пакет `mtr`
  уже CLI-only, разделения на tiny/full там нет.
- **rsync**, **lsof** — имя пакета одинаковое во всех целевых
  дистрибутивах, в базовых репах, EPEL не требуется.
- **ncdu** — в базовых репах apt/dnf (Debian/Ubuntu/Fedora); на CentOS
  Stream 9 живёт в EPEL (`ncdu 1.22`, подтверждено в контейнере) —
  аналогично `btop` в `modules/base.sh`.

## Тестирование

End-to-end (`base,diagnostics`, два прогона на идемпотентность) на
Debian 12 и CentOS Stream 9 (2026-08-25) — оба прошли без ошибок,
включая путь через EPEL для ncdu на CentOS.
