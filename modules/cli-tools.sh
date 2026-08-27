#!/usr/bin/env bash
# Установка CLI-инструментов нового поколения:
# ripgrep, fd, fzf, bat, eza, zoxide, delta, jq, httpie, curlie, direnv.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh и scripts/lib/pkg-registry.sh (нужны
# PKG_MANAGER и pkg::install).
#
# Публичная точка входа: cli::install
#
# Способ установки каждого пакета (пакетный менеджер / GitHub Releases /
# pip, порядок приоритета и обоснование) — декларативно в
# data/packages/registry.json, через общий диспетчер pkg::install (см.
# scripts/lib/pkg-registry.sh, docs/design/pkg-metadata-json.md). Этот
# модуль отвечает только за то, что специфично именно для набора CLI-тулов
# и не моделируется в реестре: симлинки на переименованные внутри пакета
# бинарники (fd-find -> fdfind, bat -> batcat на apt) и конфиг bat.
#
# pkg::install сам продолжает установку остальных пакетов, если для
# одного отвалились все способы (не роняет cli::install) — см. `|| true`
# в cli::install_packages.

set -euo pipefail

CLI_PACKAGES=(ripgrep fd fzf bat jq httpie eza delta curlie zoxide direnv)

cli::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

cli::install_packages() {
  local pkg
  for pkg in "${CLI_PACKAGES[@]}"; do
    pkg::install "$pkg" || true
  done
}

# fd-find и bat на Debian/Ubuntu ставят бинарники под именами fdfind и
# batcat (конфликт имён с другими пакетами) — добавляем симлинки в
# /usr/local/bin, чтобы `fd`/`bat` работали напрямую (не только через
# алиас `cat`, см. modules/aliases.sh). На dnf/yum переименования нет,
# симлинк создаётся, только если реального fd/bat ещё нет в PATH.
cli::ensure_symlinks() {
  if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    log::info "cli-tools: символическая ссылка fd -> $(command -v fdfind)"
  fi
  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
    log::info "cli-tools: символическая ссылка bat -> $(command -v batcat)"
  fi
}

cli::write_bat_config() {
  local src dest dest_dir
  src="$(cli::_dotfiles_dir)/config/bat.conf"
  dest_dir="$HOME/.config/bat"
  dest="$dest_dir/config"

  mkdir -p "$dest_dir"

  backup::create_if_diff "$src" "$dest" "cli-tools"

  cp "$src" "$dest"
  log::info "cli-tools: $dest обновлён"
}

cli::write_direnvrc() {
  local src dest dest_dir
  src="$(cli::_dotfiles_dir)/config/direnvrc"
  dest_dir="$HOME/.config/direnv"
  dest="$dest_dir/direnvrc"

  mkdir -p "$dest_dir"

  backup::create_if_diff "$src" "$dest" "cli-tools"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] обновил бы $dest"
    return 0
  fi

  cp "$src" "$dest"
  log::info "cli-tools: $dest обновлён"
}

cli::install() {
  cli::install_packages
  cli::ensure_symlinks
  cli::write_bat_config
  cli::write_direnvrc
  log::info "cli-tools: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/cli-tools.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
