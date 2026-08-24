# dotfiles-setup: личные алиасы.
# Устанавливается модулем modules/aliases.sh в
# ~/.config/dotfiles-setup/aliases.sh — не редактировать исходник на
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

# cs <dir> — cd + подробный листинг одной командой. Без аргумента — в $HOME.
cs() {
  cd "${1:-$HOME}" && ls -l
}

# ca <dir> — cd + листинг со скрытыми файлами. Без аргумента — в $HOME.
ca() {
  cd "${1:-$HOME}" && ls -la
}

alias cls='clear'
alias gs='git status'
alias gl='git log --oneline --graph --decorate'

# Python / uv helpers
alias uvinit='uv venv && source .venv/bin/activate'
alias uvr='uv run python'
alias uva='uv add'
