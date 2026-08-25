# .knrc: личные алиасы.
# Устанавливается модулем modules/aliases.sh в
# ~/.config/knrc/aliases.sh — не редактировать исходник на
# месте установки, правки перезапишутся при повторном запуске установки.

# cat -> bat (подсветка синтаксиса). На Debian/Ubuntu пакет bat
# ставит бинарник как batcat (конфликт имён с другим пакетом), на
# Fedora/CentOS — как bat. Алиас применяется, только если бинарник уже
# есть — не ломается, если CLI-инструменты ещё не установлены.
if command -v batcat >/dev/null 2>&1; then
  alias cat='batcat'
elif command -v bat >/dev/null 2>&1; then
  alias cat='bat'
fi

# ls/ll/la -> eza (подсветка, иконки). Применяется, только если
# бинарник уже есть — не ломается, если CLI-инструменты ещё не
# установлены.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons'
  alias ll='eza -lah --icons'
  alias la='eza -a --icons'
fi

# cs <dir> — cd + подробный листинг одной командой. Без аргумента — в $HOME.
cs() {
  cd "${1:-$HOME}" && { command -v eza >/dev/null 2>&1 && eza -lah --icons || ls -lah; }
}

# ca <dir> — cd + листинг со скрытыми файлами. Без аргумента — в $HOME.
ca() {
  cd "${1:-$HOME}" && { command -v eza >/dev/null 2>&1 && eza -a --icons || ls -a; }
}

alias cls='clear'
alias gs='git status'
alias gl='git log --oneline --graph --decorate'

# Python / uv helpers
alias uvinit='uv venv && source .venv/bin/activate'
alias uvr='uv run python'
alias uva='uv add'

# Локальные алиасы пользователя: этот файл перезаписывается install.sh при
# каждом запуске, поэтому здесь нет места для собственных настроек — они
# подключаются отдельным файлом, который install.sh не трогает.
[[ ! -f ~/.config/knrc/aliases.local.sh ]] || source ~/.config/knrc/aliases.local.sh
