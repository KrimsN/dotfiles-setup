# modules/cli-tools.sh

Ставит все 10 CLI-инструментов нового поколения (ripgrep, fd, fzf, bat,
jq, httpie, eza, delta, curlie, zoxide). Требует `scripts/lib/os-detect.sh`.

Две стратегии установки в одном модуле:

- **Через пакетный менеджер** (ripgrep, fd-find, fzf, bat, jq, httpie):
  для rhel-семейства сначала включается EPEL (`epel-release`) и, если
  доступна команда `crb`, репозиторий CRB (CodeReady Builder) — часть
  пакетов EPEL на CentOS Stream 9 (в частности httpie) требует
  зависимостей оттуда, без CRB установка падает с "conflicting
  requests". Обе операции best-effort (не валят весь модуль, если
  недоступны — актуально для Fedora, где EPEL не нужен и `crb` не
  существует).
- **Бинарником с GitHub Releases** (eza, delta/git-delta, curlie, zoxide)
  — единообразно для всех дистрибутивов, т.к. этих пакетов нет (или нет
  везде/во всех актуальных версиях) в стандартных репозиториях, особенно
  на CentOS. Скачивается musl-статик под архитектуру (`uname -m`,
  определяется через `cli::_arch_rust` x86_64/aarch64 или `cli::_arch_go`
  amd64/arm64 — у curlie goreleaser-стиль именования ассетов, у
  остальных трёх — Rust-стиль), URL резолвится через GitHub API
  (`/repos/<repo>/releases/latest`), бинарник кладётся в
  `/usr/local/bin`. Идемпотентно: пропускает скачивание, если команда с
  таким именем уже есть в PATH.

`fd-find` и `bat` на Debian/Ubuntu ставят бинарники как `fdfind` и
`batcat` (конфликт имён с другими пакетами существующими в системе) —
модуль сам создаёт симлинки `/usr/local/bin/fd`/`bat` на них, если
канонического имени ещё нет в PATH (дополняет alias `cat`→`bat`/`batcat`
из modules/aliases.sh реальным бинарником на PATH для использования из
скриптов, не только интерактивно).

**Тестирование**: end-to-end (установка + двойной запуск на
идемпотентность) в Ubuntu 24.04, Fedora 39, CentOS Stream 9 (включая
EPEL+CRB) — на всех три версии совпали ассеты, скачанные с GitHub.
Дополнительно проверена установка (без повторного прогона) на Debian 12.
