#!/usr/bin/env bash
# Установка личных shell-алиасов пользователя (cat->bat, cs).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/rcfile.sh.
#
# Публичная точка входа: aliases::install
#
# Тот же паттерн, что и у tmux-хука (см. modules/tmux.sh): снипет
# ставится в ~/.config/dotfiles-setup/aliases.sh, а подключается:
#   - из ~/.zshrc — строка уже зашита в config/zshrc (модуль zsh.sh
#     пишет .zshrc целиком из шаблона);
#   - из ~/.bashrc — управляемым блоком через rcfile::upsert_block.
#
# Пакеты, от которых зависят алиасы (например bat), этот модуль не
# ставит — это задача будущего модуля CLI-инструментов. Алиасы
# проверяют наличие бинарника сами и не ломаются, если его ещё нет.

set -euo pipefail

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/dotfiles-setup}"

aliases::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

aliases::install() {
  local snippet_src snippet_dest
  snippet_src="$(aliases::_dotfiles_dir)/config/aliases.sh"
  snippet_dest="$DOTFILES_STATE_DIR/aliases.sh"

  mkdir -p "$DOTFILES_STATE_DIR"
  cp "$snippet_src" "$snippet_dest"

  rcfile::upsert_block "$HOME/.bashrc" "aliases" \
    "[ -f \"$snippet_dest\" ] && source \"$snippet_dest\""

  echo "aliases: установлены ($snippet_dest)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/aliases.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
