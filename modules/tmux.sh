#!/usr/bin/env bash
# Установка и настройка tmux + TPM + tmux-resurrect + tmux-continuum.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh и scripts/lib/rcfile.sh.
#
# Публичная точка входа: tmux::install
#
# По умолчанию голый `tmux` подключается к уже существующей сессии,
# если она есть — см. config/tmux-autoattach.sh. Хук ставится в
# ~/.config/dotfiles-setup/tmux-autoattach.sh и подключается:
#   - из ~/.zshrc — строка уже зашита в config/zshrc (модуль zsh.sh
#     пишет .zshrc целиком из шаблона, ничего дополнительно делать не
#     нужно, файл-хук просто должен существовать на диске);
#   - из ~/.bashrc — управляемым блоком через rcfile::upsert_block,
#     т.к. .bashrc никем целиком не управляется.

set -euo pipefail

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/dotfiles-setup}"

tmux::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

tmux::install_package() {
  log::info "tmux: устанавливаю пакет tmux"
  os::pkg_install tmux
}

tmux::install_tpm() {
  local dest="$HOME/.tmux/plugins/tpm"
  if [ -d "$dest" ]; then
    log::info "tmux: TPM уже установлен, пропускаю"
  else
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$dest"
  fi
}

tmux::write_config() {
  local src dest
  src="$(tmux::_dotfiles_dir)/config/tmux.conf"
  dest="$HOME/.tmux.conf"

  # cmp — часть diffutils, не всегда стоит в минимальных образах; ставим
  # заранее (идемпотентно).
  os::pkg_install diffutils >/dev/null

  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    log::warn "tmux: существующий ~/.tmux.conf отличается — делаю бэкап в $backup"
    cp "$dest" "$backup"
  fi

  cp "$src" "$dest"
  log::info "tmux: ~/.tmux.conf обновлён"
}

tmux::install_plugins() {
  log::info "tmux: устанавливаю плагины через TPM (headless)"
  # install_plugins читает путь к TPM из переменной окружения tmux-сервера,
  # которую регистрирует сам ~/.tmux.conf при загрузке (строка `run -b
  # '~/.tmux/plugins/tpm/tpm'`) — поэтому нужен хотя бы один запущенный
  # сервер с этим конфигом, иначе install_plugins падает с
  # "TMUX_PLUGIN_MANAGER_PATH not configured".
  local bootstrap_session="_dotfiles_tpm_bootstrap"
  tmux new-session -d -s "$bootstrap_session"
  # `run -b` в tmux.conf, которым TPM регистрирует свой путь, выполняется
  # в фоне асинхронно — без небольшой паузы install_plugins стартует
  # раньше, чем переменная окружения успевает выставиться.
  sleep 1
  "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null
  tmux kill-session -t "$bootstrap_session" 2>/dev/null || true
}

tmux::install_autoattach_hook() {
  local snippet_src snippet_dest
  snippet_src="$(tmux::_dotfiles_dir)/config/tmux-autoattach.sh"
  snippet_dest="$DOTFILES_STATE_DIR/tmux-autoattach.sh"

  mkdir -p "$DOTFILES_STATE_DIR"
  cp "$snippet_src" "$snippet_dest"

  rcfile::upsert_block "$HOME/.bashrc" "tmux-autoattach" \
    "[ -f \"$snippet_dest\" ] && source \"$snippet_dest\""

  log::info "tmux: хук авто-подключения установлен ($snippet_dest)"
}

tmux::install() {
  tmux::install_package
  tmux::install_tpm
  tmux::write_config
  tmux::install_plugins
  tmux::install_autoattach_hook
  log::info "tmux: готово. Голый 'tmux' будет подключаться к существующей сессии, если она есть."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/tmux.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
