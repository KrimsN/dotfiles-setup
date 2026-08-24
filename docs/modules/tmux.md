# modules/tmux.sh

Устанавливает tmux (`os::pkg_install`), TPM (git clone в
`~/.tmux/plugins/tpm`), пишет `~/.tmux.conf` из `config/tmux.conf` (та же
схема бэкапа через `cmp`, что и у zsh.sh), ставит плагины `tmux-resurrect`
и `tmux-continuum` через headless `tpm/bin/install_plugins` — для этого
нужен хотя бы один запущенный tmux-сервер с загруженным конфигом (иначе
TPM не знает свой путь), поэтому модуль поднимает временную
detached-сессию `_dotfiles_tpm_bootstrap`, ждёт секунду (строка `run -b`
в tmux.conf асинхронна) и закрывает её после установки плагинов.

Требует `scripts/lib/os-detect.sh` и `scripts/lib/rcfile.sh` (`source`
перед этим модулем).

## Содержимое config/tmux.conf

(дополнено 2026-08-24, помимо `mouse on`, который был с самого начала):
`history-limit 50000`, `escape-time 0` (без задержки после Esc — важно
для vim/nvim внутри tmux), `renumber-windows on`, `focus-events on`,
`default-terminal 'tmux-256color'` + `terminal-overrides` для true-color;
удобные сплиты `|`/`-` (сохраняют `pane_current_path`, заменяют дефолтные
`%`/`"`), `prefix + r` — reload конфига без выхода из tmux; кастомный
status-bar (имя сессии, список окон, дата/время, hostname) вместо
дефолтного минималистичного. Vi-style keys в copy-mode осознанно не
добавлены — пользователь их не запрашивал.

## Поведение по умолчанию (зафиксировано пользователем)

Голый `tmux` без аргументов подключается к уже существующей сессии, если
она есть, иначе создаёт новую; с явными аргументами (`tmux new -s foo` и
т.п.) ведёт себя как обычно. Реализовано shell-функцией в
`config/tmux-autoattach.sh`, которая ставится в
`~/.config/dotfiles-setup/tmux-autoattach.sh` и подключается из
`~/.zshrc` (условная строка уже зашита в `config/zshrc` — работает
независимо от порядка запуска zsh.sh/tmux.sh) и из `~/.bashrc` через
`rcfile::upsert_block` (т.к. `.bashrc` не управляется целиком).

**Тестирование**: end-to-end в контейнере Ubuntu 24.04: установка,
двойной запуск (идемпотентность — TPM/пакет не переустанавливаются,
`.bashrc`-блок не дублируется), и поведенческая проверка под реальным pty
(`script`) — bare `tmux` подключается к существующей сессии вместо
создания новой, а `tmux new -s <name>` по-прежнему создаёт отдельную
сессию.
