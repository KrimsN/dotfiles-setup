# modules/extras.sh

tldr (через пакетный менеджер, на CentOS/RHEL — через EPEL) и fastfetch
(единообразно на всех дистрибутивах через `github_release::install`,
т.к. пакета нет в репах Debian/Ubuntu вообще, а в Fedora он и вовсе
удалён).

**Нюанс с fastfetch**: у него в GitHub Releases есть ассет
`fastfetch-musl-amd64.tar.gz`, но вопреки названию он не статический —
реально слинкован с musl libc динамически (`NEEDED
libc.musl-x86_64.so.1`), и на glibc-дистрибутивах (все наши целевые) не
запускается ("required file not found", нет musl-рантайма). Использован
обычный `fastfetch-linux-<arch>.tar.gz` (glibc-сборка) вместо него —
работает везде. В отличие от eza/delta/zoxide, где musl-ассеты — честный
статик (там всё ок, проверено).

Требует `scripts/lib/os-detect.sh`, `scripts/lib/epel.sh`,
`scripts/lib/github-release.sh`.

**Тестирование**: end-to-end (установка + идемпотентность) на
Ubuntu 24.04, Fedora (актуальная), CentOS Stream 9 (подтверждена ветка
EPEL для tldr).
