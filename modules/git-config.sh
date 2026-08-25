#!/usr/bin/env bash
# Настройка ~/.gitconfig: pager (delta), редактор, разумные дефолты
# самого git и глобальный gitignore.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh.
#
# Публичная точка входа: git_config::install
#
# Настраиваем через `git config --global <key> <value>`, а НЕ
# копированием готового ~/.gitconfig: копирование затёрло бы
# собственные настройки пользователя (и его user.name/user.email),
# а `git config` идемпотентен по природе — повторный прогон просто
# перезапишет те же ключи теми же значениями.
#
# delta и nvim ставятся другими модулями (cli-tools.sh и nvim.sh), и
# оба могут быть не выбраны при установке. Поэтому все ключи, которые
# ссылаются на конкретный бинарник, выставляются только под guard'ом
# `command -v` — тот же приём, что в config/aliases.sh для bat/eza:
# конфиг, ссылающийся на несуществующий pager, ломает вообще любой
# `git diff`, а не только красивый вывод.

set -euo pipefail

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"

git_config::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

git_config::_set() {
  git config --global "$1" "$2"
}

# Значение уже выставлено в ~/.gitconfig (или в любом другом файле,
# который git считает глобальным)?
git_config::_has() {
  git config --global --get "$1" >/dev/null 2>&1
}

git_config::setup_pager() {
  if ! command -v delta >/dev/null 2>&1; then
    log::warn "git-config: delta не найден в PATH, pager не настраиваю (модуль cli-tools не устанавливался?)"
    return 0
  fi

  log::info "git-config: настраиваю delta как pager"
  git_config::_set core.pager delta
  git_config::_set interactive.diffFilter "delta --color-only"
  git_config::_set delta.navigate true
  git_config::_set delta.line-numbers true
  # zdiff3 показывает в конфликте общего предка — с delta это заметно
  # полезнее дефолтного merge-стиля.
  git_config::_set merge.conflictStyle zdiff3
}

git_config::setup_editor() {
  if ! command -v nvim >/dev/null 2>&1; then
    log::warn "git-config: nvim не найден в PATH, core.editor не трогаю (модуль nvim не устанавливался?)"
    return 0
  fi

  log::info "git-config: core.editor = nvim"
  git_config::_set core.editor nvim
}

git_config::setup_defaults() {
  log::info "git-config: выставляю общие дефолты git"
  git_config::_set init.defaultBranch master
  git_config::_set pull.rebase true
  git_config::_set push.autoSetupRemote true
  git_config::_set rerere.enabled true
  git_config::_set diff.algorithm histogram
}

git_config::setup_excludes() {
  local snippet_src snippet_dest config_value
  snippet_src="$(git_config::_dotfiles_dir)/config/gitignore_global"
  snippet_dest="$DOTFILES_STATE_DIR/gitignore_global"

  mkdir -p "$DOTFILES_STATE_DIR"
  cp "$snippet_src" "$snippet_dest"

  # В ~/.gitconfig пишем путь через `~`, а не абсолютный: git сам
  # раскрывает `~/` в значении core.excludesFile, а такой конфиг
  # переносим между машинами с разными $HOME.
  case "$snippet_dest" in
    "$HOME"/*) config_value="~/${snippet_dest#"$HOME"/}" ;;
    *)         config_value="$snippet_dest" ;;
  esac

  git_config::_set core.excludesFile "$config_value"
  log::info "git-config: глобальный gitignore установлен ($snippet_dest)"
}

# user.name / user.email — единственное, что нельзя выставить за
# пользователя. Спрашиваем через /dev/tty (а не stdin: при
# `curl ... | bash` stdin занят телом скрипта — см. CLAUDE.md, раздел
# "Механизм конфигурации"). Уже заполненные значения не трогаем и не
# переспрашиваем — это делает повторный прогон полностью молчаливым.
# `[ -r /dev/tty ]` здесь недостаточно: в контейнере без выделенного
# терминала (docker run без -t, CI) файл /dev/tty существует и проходит
# проверку -r, но открытие падает с "No such device or address" — что и
# ловили при тестировании модуля. Единственная надёжная проверка —
# попробовать открыть устройство.
git_config::_tty_available() {
  { : < /dev/tty; } 2>/dev/null
}

git_config::_ask_identity_field() {
  local key="$1" question="$2" answer=""

  if git_config::_has "$key"; then
    log::info "git-config: $key уже выставлен ($(git config --global --get "$key")), не трогаю"
    return 0
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || ! git_config::_tty_available; then
    return 0
  fi

  read -r -p "$(log::prompt "$question (пусто — пропустить): ")" answer < /dev/tty || answer=""
  if [ -n "$answer" ]; then
    git_config::_set "$key" "$answer"
  fi
}

git_config::setup_identity() {
  git_config::_ask_identity_field user.name "git user.name"
  git_config::_ask_identity_field user.email "git user.email"
}

git_config::install() {
  if ! command -v git >/dev/null 2>&1; then
    log::err "git-config: git не найден в PATH — сначала поставь модуль base"
    return 1
  fi

  git_config::setup_defaults
  git_config::setup_pager
  git_config::setup_editor
  git_config::setup_excludes
  git_config::setup_identity
  log::info "git-config: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/git-config.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
