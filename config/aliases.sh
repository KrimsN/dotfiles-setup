# shellcheck shell=bash
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
  cd "${1:-$HOME}" || return
  if command -v eza >/dev/null 2>&1; then
    eza -lah --icons
  else
    ls -lah
  fi
}

# ca <dir> — cd + листинг со скрытыми файлами. Без аргумента — в $HOME.
ca() {
  cd "${1:-$HOME}" || return
  if command -v eza >/dev/null 2>&1; then
    eza -a --icons
  else
    ls -a
  fi
}

alias cls='clear'
alias gs='git status'
alias gl='git log --oneline --graph --decorate'

# Python / uv helpers
alias uvinit='uv venv && source .venv/bin/activate'
alias uvr='uv run python'
alias uva='uv add'

# dvinit [layout] — создать .envrc в текущем каталоге (если его ещё нет)
# с директивой `layout <layout>` и слоями dotenv_if_exists (.env / .env.local
# / .env.$USER), затем сразу выполнить `direnv allow`. Без аргумента
# угадывает layout по файлам проекта: pyproject.toml/uv.lock -> uv (наш
# layout_uv из ~/.config/direnv/direnvrc), go.mod -> go, package.json ->
# node, иначе тоже uv. Существующий .envrc не трогает — только
# допечатывает direnv allow.
dvinit() {
  if ! command -v direnv >/dev/null 2>&1; then
    echo "dvinit: direnv не установлен" >&2
    return 1
  fi

  local layout="${1:-}"
  if [[ -z "$layout" ]]; then
    if [[ -f "pyproject.toml" || -f "uv.lock" ]]; then
      layout="uv"
    elif [[ -f "go.mod" ]]; then
      layout="go"
    elif [[ -f "package.json" ]]; then
      layout="node"
    else
      layout="uv"
    fi
  fi

  if [[ -f ".envrc" ]]; then
    echo "dvinit: .envrc уже существует, оставляю как есть" >&2
  else
    cat > .envrc <<EOF
layout $layout

dotenv_if_exists .env
dotenv_if_exists .env.local   # опциональные локальные переопределения, в .gitignore
dotenv_if_exists .env.\$USER  # опционально под конкретного разработчика
EOF
    echo "dvinit: создан .envrc (layout $layout)" >&2
  fi

  direnv allow .
}

# Локальные алиасы пользователя: этот файл перезаписывается install.sh при
# каждом запуске, поэтому здесь нет места для собственных настроек — они
# подключаются отдельным файлом, который install.sh не трогает.
# shellcheck disable=SC1090
[[ ! -f ~/.config/knrc/aliases.local.sh ]] || source ~/.config/knrc/aliases.local.sh
