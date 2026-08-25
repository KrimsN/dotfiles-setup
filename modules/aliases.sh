#!/usr/bin/env bash
# Установка личных shell-алиасов пользователя (cat->bat, cs).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/rcfile.sh.
#
# Публичная точка входа: aliases::install
#
# Тот же паттерн, что и у tmux-хука (см. modules/tmux.sh): снипет
# ставится в ~/.config/knrc/aliases.sh, а подключается:
#   - из ~/.zshrc — строка уже зашита в config/zshrc (модуль zsh.sh
#     пишет .zshrc целиком из шаблона);
#   - из ~/.bashrc — управляемым блоком через rcfile::upsert_block.
#
# Пакеты, от которых зависят алиасы (например bat), этот модуль не
# ставит — это задача будущего модуля CLI-инструментов. Алиасы
# проверяют наличие бинарника сами и не ломаются, если его ещё нет.

set -euo pipefail

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"

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

  aliases::create_local_file

  log::info "aliases: установлены ($snippet_dest)"
}

# ~/.config/knrc/aliases.local.sh — точка расширения для собственных
# алиасов пользователя (см. подключение в config/aliases.sh). install.sh
# его не трогает при повторных запусках, поэтому создаём только если
# файла ещё нет.
aliases::create_local_file() {
  local dest="$DOTFILES_STATE_DIR/aliases.local.sh"

  if [ -f "$dest" ]; then
    log::info "aliases: $dest уже существует, не трогаю"
    return 0
  fi

  cat > "$dest" <<'EOF'
# ~/.config/knrc/aliases.local.sh — сюда пишите все алиасы, которые
# хотите сохранить между запусками install.sh. Этот файл он не создаёт
# заново и не перезаписывает, в отличие от ~/.config/knrc/aliases.sh.
EOF
  log::info "aliases: создан $dest"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/aliases.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
