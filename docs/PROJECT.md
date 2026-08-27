# .krimsnrc (`.knrc`) — документация проекта

Набор скриптов для быстрой настройки unix-окружения на свежей машине.
Поддерживаемые дистрибутивы: Ubuntu, Debian, Fedora, CentOS.

Быстрый старт, флаги `install.sh`, `knrc doctor`/`knrc uninstall` — см.
[README.md](../README.md). Здесь — полный список того, что ставится,
принятые решения по составу и текущий статус реализации.

## Ключевые требования

- **zsh + oh-my-zsh** — можно ставить как login-shell по умолчанию ИЛИ
  просто устанавливать бинарник/конфиг без смены shell (управляется
  флагом запуска / переменной окружения, не хардкодится).
- **tmux** — конфиг + базовый набор плагинов (TPM).
- **Powerlevel10k** — тема промпта обязательна (требует Nerd Font на
  клиентской стороне — учитывать при установке/документации).
- Быстрое развёртывание одной командой (`curl ... | bash`) с
  интерактивной настройкой внутри скрипта.

## Список программ

### Базовый набор

git, curl, wget, vim, neovim, htop, btop, tree, unzip, zip, diffutils
— neovim ставится не пакетом, а свежим бинарником с GitHub Releases +
конфиг + lazy.nvim, см. [docs/modules/nvim.md](modules/nvim.md).

### CLI-инструменты нового поколения

ripgrep (rg), fd, fzf, bat, eza, zoxide, delta, jq, httpie, curlie,
direnv — автоактивация `.venv` (через уже установленный uv) и прочих
project-scoped переменных при `cd` в каталог с `.envrc`; хук
`eval "$(direnv hook zsh)"` в `config/zshrc` подключается после
инициализации oh-my-zsh, по образцу fzf/zoxide, см.
[docs/modules/cli-tools.md](modules/cli-tools.md).

### Git-экосистема

gh, git-delta (см. выше, не дублировать установку) — lazygit исключён
по решению пользователя.

Настройка самого git (`~/.gitconfig`: delta как pager, core.editor,
дефолты git, глобальный gitignore) — отдельный модуль
`modules/git-config.sh`, см.
[docs/modules/git-config.md](modules/git-config.md).

### tmux-экосистема

tmux, TPM, tmux-resurrect, tmux-continuum — tmuxinator исключён по
решению пользователя.

### Контейнеры

docker (docker compose входит в современный docker, отдельно не
ставить).

### Python

uv (менеджер пакетов и версий Python, официальный `curl | sh`-инсталлер
astral.sh) + ruff (линтер/форматтер, ставится через `uv tool install`).
Toolchain Rust (rustup/cargo/rustc) исключён — решение пользователя, uv
и ruff это готовые бинарники, компилятор не нужен. Отдельные
pyenv/pipx/poetry не ставятся — их функциональность покрывает uv. См.
[docs/modules/python-tools.md](modules/python-tools.md).

### Прочее

tldr, fastfetch — изначально был выбран neofetch, но проект archived и
убран из репозиториев Fedora; заменён на fastfetch (активно
поддерживаемый форк) единообразно на всех дистрибутивах, см.
[docs/modules/extras.md](modules/extras.md).

### Диагностические утилиты

rsync, dig (dnsutils на apt / bind-utils на dnf-yum), ncdu (на CentOS —
через EPEL), lsof, mtr (mtr-tiny на apt, чтобы не тянуть
GUI-зависимости метапакета mtr; mtr на dnf/yum), см.
[docs/modules/diagnostics.md](modules/diagnostics.md).

### Neovim

Конфиг (init.lua) + менеджер плагинов (lazy.nvim) + базовый набор
плагинов: дерево файлов, статус-бар, нечёткий поиск, treesitter,
цветовая схема. LSP/автодополнение исключены — решение пользователя,
пока не нужны. См. [docs/modules/nvim.md](modules/nvim.md).

### Тема промпта

Powerlevel10k — обязательна, не опциональна.

### Шрифты

JetBrainsMono Nerd Font, FiraCode Nerd Font — нужны для корректного
отображения иконок Powerlevel10k. Ставятся модулем `modules/fonts.sh`
(файлы + fc-cache), выбор шрифта в конкретном терминальном эмуляторе —
вручную, единым способом для всех терминалов автоматизировать нельзя
(см. [docs/modules/fonts.md](modules/fonts.md)).

## Плагины oh-my-zsh

Встроенные (через `plugins=(...)` в `.zshrc`): git, sudo,
command-not-found, extract, colored-man-pages, history-substring-search,
docker, docker-compose.

Внешние (клонируются в `$ZSH_CUSTOM/plugins/`): zsh-autosuggestions,
fast-syntax-highlighting, zsh-completions.

Примечание: zoxide ставится как отдельная программа (см.
CLI-инструменты) и подключает себя сам — отдельный oh-my-zsh плагин `z`
не нужен, дублирования избегать.

## Команда `knrc`

Операции над **уже настроенной** машиной живут не в `install.sh`, а в
отдельном CLI. `install.sh` ставит тонкий шим `~/.local/bin/knrc`,
который делает `exec` на `scripts/knrc.sh` в каталоге репозитория —
обновление CLI это `git pull`, sudo не требуется.

- `knrc doctor [--modules=LIST]` — диагностика, см.
  [docs/modules/doctor.md](modules/doctor.md).
- `knrc install [флаги]` — прогнать `install.sh`.
- `knrc update [--dry-run]` — обновить локальный клон (`git pull
  --ff-only`) и перезапустить `install.sh`, см.
  [docs/modules/update.md](modules/update.md).
- `knrc uninstall [--dry-run|--force|--modules=LIST]` — откат
  установки, см. [docs/modules/uninstall.md](modules/uninstall.md).
- `knrc harden-ssh [--dry-run|--force|--rollback]` — опционально, только
  по явному запросу: минимальный харденинг SSH этой машины (root-логин
  + вход по паролю) после подтверждённого доступа по ключу. Не входит в
  `KNRC_ALL_MODULES`, не участвует в `doctor`/`uninstall` — свой план и
  свой откат, см. [docs/modules/harden-ssh.md](modules/harden-ssh.md).
- Из клона то же самое доступно как `bash scripts/knrc.sh <команда>`,
  без установки шима.

## Статус

Проект функционально завершён: все модули из списка программ написаны
и протестированы (14 модулей в `KNRC_ALL_MODULES`, включая nvim,
python-tools, git-config, ssh-config и diagnostics; плюс опциональный
`zsh-terminal-app` вне `KNRC_ALL_MODULES`), есть единый лаунчер
`install.sh`, работающий как через `curl | bash` на чистой машине (без
git/curl), так и из склонированного репозитория, и команда `knrc` для
операций над уже настроенной машиной (`knrc doctor`, `knrc update`,
`knrc uninstall`, `knrc harden-ssh`).

### Реализованные модули

Детали реализации, реальные баги, найденные при тестировании, и
покрытие тестами — по одному файлу на модуль в `docs/modules/`:

| Модуль | Заметки |
|---|---|
| `scripts/lib/os-detect.sh` | [docs/modules/os-detect.md](modules/os-detect.md) |
| `modules/zsh.sh` | [docs/modules/zsh.md](modules/zsh.md) |
| `scripts/lib/rcfile.sh` | [docs/modules/rcfile.md](modules/rcfile.md) |
| `scripts/lib/backup.sh` | [docs/modules/backup.md](modules/backup.md) |
| `scripts/lib/localbin.sh` | [docs/modules/localbin.md](modules/localbin.md) |
| `scripts/lib/modules.sh` | [docs/modules/modules-list.md](modules/modules-list.md) |
| `modules/tmux.sh` | [docs/modules/tmux.md](modules/tmux.md) |
| `modules/nvim.sh` | [docs/modules/nvim.md](modules/nvim.md) |
| `modules/aliases.sh` | [docs/modules/aliases.md](modules/aliases.md) |
| `modules/cli-tools.sh` | [docs/modules/cli-tools.md](modules/cli-tools.md) |
| `modules/git-ecosystem.sh` | [docs/modules/git-ecosystem.md](modules/git-ecosystem.md) |
| `modules/git-config.sh` | [docs/modules/git-config.md](modules/git-config.md) |
| `modules/ssh-config.sh` | [docs/modules/ssh-config.md](modules/ssh-config.md) |
| `modules/docker.sh` | [docs/modules/docker.md](modules/docker.md) |
| `modules/python-tools.sh` | [docs/modules/python-tools.md](modules/python-tools.md) |
| `modules/diagnostics.sh` | [docs/modules/diagnostics.md](modules/diagnostics.md) |
| `scripts/lib/epel.sh` | [docs/modules/epel.md](modules/epel.md) |
| `modules/base.sh` | [docs/modules/base.md](modules/base.md) |
| `scripts/lib/github-release.sh` | [docs/modules/github-release.md](modules/github-release.md) |
| `scripts/lib/log.sh` | [docs/modules/log.md](modules/log.md) |
| `modules/extras.sh` | [docs/modules/extras.md](modules/extras.md) |
| `install.sh` | [docs/modules/install.md](modules/install.md) |
| `scripts/knrc.sh` + `scripts/doctor.sh` (команда `knrc doctor`) | [docs/modules/doctor.md](modules/doctor.md) |
| `scripts/update.sh` (команда `knrc update`) | [docs/modules/update.md](modules/update.md) |
| `scripts/uninstall.sh` + `scripts/lib/state.sh` (команда `knrc uninstall`) | [docs/modules/uninstall.md](modules/uninstall.md) |
| `scripts/harden-ssh.sh` (опциональная команда `knrc harden-ssh`, вне `ALL_MODULES`) | [docs/modules/harden-ssh.md](modules/harden-ssh.md) |
| `modules/fonts.sh` | [docs/modules/fonts.md](modules/fonts.md) |
| `modules/zsh-terminal-app.sh` (опциональный, вне `ALL_MODULES`) | [docs/modules/zsh-terminal-app.md](modules/zsh-terminal-app.md) |
