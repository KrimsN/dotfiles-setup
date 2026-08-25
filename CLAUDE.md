# .krimsnrc

Внутренний технический идентификатор проекта (пути состояния, маркеры
в rc-файлах, комментарии "Managed by ...") — `knrc`, короткая форма
полного имени `.krimsnrc`.

## Цель проекта

Набор скриптов для быстрой настройки unix-окружения на свежей машине.
Поддерживаемые дистрибутивы: Ubuntu, Debian, Fedora, CentOS.

Ключевые требования:

- **zsh + oh-my-zsh** — можно ставить как login-shell по умолчанию ИЛИ
  просто устанавливать бинарник/конфиг без смены shell (управляется флагом
  запуска / переменной окружения, не хардкодится).
- **tmux** — конфиг + базовый набор плагинов (TPM).
- **Powerlevel10k** — тема промпта обязательна (требует Nerd Font на
  клиентской стороне — учитывать при установке/документации).
- Быстрое развёртывание одной командой (`curl ... | bash`) с интерактивной
  настройкой внутри скрипта — см. раздел "Механизм конфигурации".

## Механизм конфигурации (зафиксировано пользователем)

- **По умолчанию — интерактивный режим.** Скрипт сам задаёт вопросы (выбор
  shell по умолчанию/альтернативного, какие опциональные компоненты
  ставить и т.п.) прямо во время выполнения через `read ... < /dev/tty`,
  а не через stdin — это необходимо, чтобы вопросы работали и при
  `curl ... | bash` (stdin в этом случае занят телом скрипта).
- **Неинтерактивный fallback.** Если `/dev/tty` недоступен (CI, cron,
  `bash < install.sh` и т.п.) — не падать, а использовать значения по
  умолчанию либо взять их из env-переменных.
- **Явный пропуск вопросов.** Флаг `--yes` (или `NONINTERACTIVE=1`)
  принудительно отключает все вопросы и использует
  дефолты/env-переменные — нужен для автоматизации и для идемпотентных
  повторных запусков на уже настроенной машине.
- **Dry-run.** Флаг `--dry-run` (или `DRY_RUN=1`) — показать, что было бы
  сделано, не меняя ничего на диске/в системе (пакеты, rc-блоки,
  бинарники с GitHub Releases). Перехват на уровне общих точек мутации
  в `scripts/lib/*`, не на уровне отдельных модулей — не 100% покрытие,
  см. [docs/modules/install.md](docs/modules/install.md).
- **Лог последнего прогона.** Каждый запуск `install.sh` дописывает
  строку в `~/.knrc.log` (время, режим, модули, дистрибутив, результат).
- Конкретные имена env-переменных/флагов под отдельные опции (режим shell,
  список опциональных пакетов и т.д.) определить при реализации
  соответствующего модуля.

## Список программ (зафиксировано пользователем)

### Базовый набор
git, curl, wget, vim, neovim, htop, btop, tree, unzip, zip, diffutils
— neovim ставится не пакетом, а свежим бинарником с GitHub Releases +
конфиг + lazy.nvim, см. modules/nvim.sh и [docs/modules/nvim.md](docs/modules/nvim.md).

### CLI-инструменты нового поколения
ripgrep (rg), fd, fzf, bat, eza, zoxide, delta, jq, httpie, curlie

### Git-экосистема
gh (уже используется в этом репо), git-delta (см. выше, не дублировать
установку)
— lazygit исключён по решению пользователя.

Настройка самого git (`~/.gitconfig`: delta как pager, core.editor,
дефолты git, глобальный gitignore) — отдельный модуль
modules/git-config.sh, см. [docs/modules/git-config.md](docs/modules/git-config.md).

### tmux-экосистема
tmux, TPM, tmux-resurrect, tmux-continuum
— tmuxinator исключён по решению пользователя.

### Контейнеры
docker (docker compose входит в современный docker, отдельно не ставить)

### Python
uv (менеджер пакетов и версий Python, официальный `curl | sh`-инсталлер
astral.sh) + ruff (линтер/форматтер, ставится через `uv tool install`).
Toolchain Rust (rustup/cargo/rustc) исключён — решение пользователя, uv
и ruff это готовые бинарники, компилятор не нужен. Отдельные
pyenv/pipx/poetry не ставятся — их функциональность покрывает uv. См.
modules/python-tools.sh.

### Прочее
tldr, fastfetch — изначально был выбран neofetch, но проект archived и
убран из репозиториев Fedora; заменён на fastfetch (активно
поддерживаемый форк) единообразно на всех дистрибутивах — решение
пользователя, см. modules/extras.sh.

### Диагностические утилиты
rsync, dig (dnsutils на apt / bind-utils на dnf-yum), ncdu (на CentOS —
через EPEL), lsof, mtr (mtr-tiny на apt, чтобы не тянуть GUI-зависимости
метапакета mtr; mtr на dnf/yum) — добавлены по согласованию с
пользователем (не входили в изначальный список), см. modules/diagnostics.md.

### Neovim
Конфиг (init.lua) + менеджер плагинов (lazy.nvim) + базовый набор
плагинов: дерево файлов, статус-бар, нечёткий поиск, treesitter,
цветовая схема. LSP/автодополнение исключены — решение пользователя,
пока не нужны. См. modules/nvim.sh.

### Тема промпта
Powerlevel10k — обязательна, не опциональна.

### Шрифты
JetBrainsMono Nerd Font, FiraCode Nerd Font — нужны для корректного
отображения иконок Powerlevel10k. Ставятся модулем modules/fonts.sh
(файлы + fc-cache), выбор шрифта в конкретном терминальном эмуляторе
— вручную, единым способом для всех терминалов автоматизировать
нельзя (см. сам модуль).

## Плагины oh-my-zsh (зафиксировано пользователем — весь список включаем)

Встроенные (через `plugins=(...)` в `.zshrc`):
git, sudo, command-not-found, extract, colored-man-pages,
history-substring-search, docker, docker-compose

Внешние (устанавливаются отдельно, клонируются в
`$ZSH_CUSTOM/plugins/`):
zsh-autosuggestions, fast-syntax-highlighting, zsh-completions

Примечание: zoxide ставится как отдельная программа (см. CLI-инструменты) и
подключает себя сам — отдельный oh-my-zsh плагин `z` не нужен, дублирования
избегать.

## Статус

Проект функционально завершён: все модули из списка программ написаны
и протестированы (14 модулей в ALL_MODULES, включая nvim,
python-tools, git-config, ssh-config и diagnostics; плюс опциональный
zsh-terminal-app вне ALL_MODULES), есть единый лаунчер
`install.sh`, работающий как через `curl | bash` на чистой машине (без
git/curl), так и из склонированного репозитория.

### Реализованные модули

Детали реализации, реальные баги, найденные при тестировании, и покрытие
тестами — по одному файлу на модуль в `docs/modules/`:

| Модуль | Заметки |
|---|---|
| `scripts/lib/os-detect.sh` | [docs/modules/os-detect.md](docs/modules/os-detect.md) |
| `modules/zsh.sh` | [docs/modules/zsh.md](docs/modules/zsh.md) |
| `scripts/lib/rcfile.sh` | [docs/modules/rcfile.md](docs/modules/rcfile.md) |
| `modules/tmux.sh` | [docs/modules/tmux.md](docs/modules/tmux.md) |
| `modules/nvim.sh` | [docs/modules/nvim.md](docs/modules/nvim.md) |
| `modules/aliases.sh` | [docs/modules/aliases.md](docs/modules/aliases.md) |
| `modules/cli-tools.sh` | [docs/modules/cli-tools.md](docs/modules/cli-tools.md) |
| `modules/git-ecosystem.sh` | [docs/modules/git-ecosystem.md](docs/modules/git-ecosystem.md) |
| `modules/git-config.sh` | [docs/modules/git-config.md](docs/modules/git-config.md) |
| `modules/ssh-config.sh` | [docs/modules/ssh-config.md](docs/modules/ssh-config.md) |
| `modules/docker.sh` | [docs/modules/docker.md](docs/modules/docker.md) |
| `modules/python-tools.sh` | [docs/modules/python-tools.md](docs/modules/python-tools.md) |
| `modules/diagnostics.sh` | [docs/modules/diagnostics.md](docs/modules/diagnostics.md) |
| `scripts/lib/epel.sh` | [docs/modules/epel.md](docs/modules/epel.md) |
| `modules/base.sh` | [docs/modules/base.md](docs/modules/base.md) |
| `scripts/lib/github-release.sh` | [docs/modules/github-release.md](docs/modules/github-release.md) |
| `scripts/lib/log.sh` | [docs/modules/log.md](docs/modules/log.md) |
| `modules/extras.sh` | [docs/modules/extras.md](docs/modules/extras.md) |
| `install.sh` | [docs/modules/install.md](docs/modules/install.md) |
| `modules/fonts.sh` | [docs/modules/fonts.md](docs/modules/fonts.md) |
| `modules/zsh-terminal-app.sh` (опциональный, вне ALL_MODULES) | [docs/modules/zsh-terminal-app.md](docs/modules/zsh-terminal-app.md) |

## Архитектурные принципы (для будущей реализации)

- Определение дистрибутива/пакетного менеджера (`apt`/`dnf`/`yum`) —
  отдельный модуль, не дублировать логику в каждом скрипте.
- Идемпотентность: повторный запуск не должен ломать уже настроенное
  окружение.
- Каждый компонент (zsh, tmux, отдельные программы) — отдельный
  устанавливаемый модуль, который можно включать/выключать независимо.
- Не смешивать логику разных дистрибутивов в одном месте без явного
  диспетчера.

## Как работать над этим проектом

- Прежде чем писать install-логику — уточнять у пользователя недостающие
  детали (список программ, механизм конфигурации, поведение по умолчанию
  для смены shell и т.п.), а не додумывать самостоятельно.
- Каждый добавляемый скрипт должен быть протестирован хотя бы в одном
  контейнере целевого дистрибутива, если есть возможность — тестируй через
  `.claude/skills/test-module/` (см. SKILL.md) вместо разового ad hoc
  прогона, чтобы шаги тестирования переиспользовались между сессиями.
- Новый модуль документируется отдельным файлом в `docs/modules/`
  (что делает, реальные баги, найденные при тестировании, покрытие
  тестами), а не инлайном в этом файле — см. существующие файлы как
  образец.
