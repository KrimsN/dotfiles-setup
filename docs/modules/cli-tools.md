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

  Каждый из шести пакетов ставится **по отдельности** через
  `os::pkg_try_install` (не единым вызовом, в отличие от
  `os::pkg_install`), чтобы неудача одного не роняла установку
  остальных. Это нужно, например, на корпоративных машинах, где
  дефолтные репозитории подменены на внутренние зеркала без части
  пакетов. Если код возврата `apt`/`dnf` для конкретного пакета
  ненулевой, `cli::fallback` переключается на альтернативную установку
  для этого пакета (см. `cli::fallback_*`):
  - ripgrep, fd, fzf, bat — статический musl/goreleaser-бинарник с
    GitHub Releases через `github_release::install` (тот же механизм,
    что у eza/delta/curlie/zoxide ниже).
  - jq — тоже GitHub Releases, но jq публикует голый бинарник без
    архива (`jq-linux-<arch>`), поэтому `github_release::install`
    умеет, помимо `.tar.gz`, класть такой ассет напрямую.
  - httpie — статических бинарников на GitHub Releases нет (чистый
    python-пакет), fallback ставит через `pip3 install --user httpie`
    (ставит `python3-pip`, если его тоже нет).
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

Конфиг bat (`config/bat.conf` → `~/.config/bat/config`): тема
`TwoDark`, стиль `numbers,changes,header`, `--paging=auto`.
Разворачивается по тому же паттерну, что и `~/.tmux.conf` в
modules/tmux.sh — бэкап с таймстампом при отличии от уже существующего
файла, иначе перезапись.

**Тестирование**: end-to-end (установка + двойной запуск на
идемпотентность) в Ubuntu 24.04, Fedora 39, CentOS Stream 9 (включая
EPEL+CRB) — на всех три версии совпали ассеты, скачанные с GitHub.
Дополнительно проверена установка (без повторного прогона) на Debian 12.
Конфиг bat дополнительно перепроверен через `scripts/test-module.sh
base,cli-tools` на Ubuntu 24.04 и Fedora (latest, dnf5) — записывается
идемпотентно на обоих прогонах.

**Тестирование fallback-пути**: проверено на Ubuntu 24.04 —
`ripgrep` заблокирован через `/etc/apt/preferences.d` (Pin-Priority
-1, имитация отсутствия пакета в корпоративном репозитории),
`apt-get install` вернул `E: Package 'ripgrep' has no installation
candidate`, `cli::install_pkg_group` поймал ненулевой код,
переключился на `cli::fallback_ripgrep`, `rg` встал в
`/usr/local/bin` с GitHub Releases, установка остальных пяти пакетов
(fzf, jq, httpie, bat, fd-find) продолжилась штатно через apt без
прерывания. Пути `cli::fallback_fd`, `cli::fallback_fzf`,
`cli::fallback_bat`, `cli::fallback_jq`, `cli::fallback_httpie` тем же
способом не перепроверялись — при следующем изменении этой ветки
логики стоит прогнать аналогично (pin нужного пакета на -1).
