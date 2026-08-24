# modules/base.sh

Базовый набор: git, curl, wget, vim, htop, btop, tree, unzip, zip,
diffutils — одним вызовом `os::pkg_install` после `epel::ensure` (btop на
CentOS живёт только в EPEL, остальное — в базовых репах везде). `neovim`
в этот список не входит (был здесь изначально) — свежий бинарник ставит
отдельный `modules/nvim.sh` с GitHub Releases (см. [nvim.md](nvim.md)),
пакетную версию не дублируем. Требует `scripts/lib/os-detect.sh` и
`scripts/lib/epel.sh`.

**Тестирование**: end-to-end на Ubuntu 24.04 (включая идемпотентность),
Fedora (актуальная), CentOS Stream 9 (подтверждён путь через EPEL для
btop) и Debian 12 — на Debian дополнительно перепроверено, что
`cli-tools.sh` продолжает работать после рефакторинга EPEL в общую
библиотеку.
