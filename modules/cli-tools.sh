#!/usr/bin/env bash
# Установка CLI-инструментов нового поколения:
# ripgrep, fd, fzf, bat, eza, zoxide, delta, jq, httpie, curlie.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh, scripts/lib/epel.sh и
# scripts/lib/github-release.sh (нужны OS_FAMILY, os::pkg_install,
# epel::ensure, github_release::install).
#
# Публичная точка входа: cli::install
#
# Стратегия установки:
#   - ripgrep, fd, fzf, bat, jq, httpie — через пакетный менеджер
#     (для rhel-семейства предварительно включаем EPEL через
#     epel::ensure, там живёт большинство из них).
#   - eza, delta, curlie, zoxide — их нет (или нет везде/во всех
#     версиях) в стандартных репах целевых дистрибутивов, поэтому
#     ставим статическими musl-бинарниками напрямую с GitHub Releases
#     — одинаково для всех дистрибутивов, без ветвления по OS_FAMILY.

set -euo pipefail

cli::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

cli::install_eza() {
  github_release::install "eza-community/eza" \
    "eza_$(github_release::arch_rust)-unknown-linux-musl\.tar\.gz$" "eza" "eza"
}

cli::install_delta() {
  github_release::install "dandavison/delta" \
    "delta-.*-$(github_release::arch_rust)-unknown-linux-musl\.tar\.gz$" "delta" "delta"
}

cli::install_curlie() {
  github_release::install "rs/curlie" \
    "curlie_.*_linux_$(github_release::arch_go)\.tar\.gz$" "curlie" "curlie"
}

cli::install_zoxide() {
  github_release::install "ajeetdsouza/zoxide" \
    "zoxide-.*-$(github_release::arch_rust)-unknown-linux-musl\.tar\.gz$" "zoxide" "zoxide"
}

cli::install_pkg_group() {
  epel::ensure
  echo "cli-tools: устанавливаю ripgrep, fd, fzf, bat, jq, httpie через пакетный менеджер"
  os::pkg_install ripgrep fzf jq httpie bat fd-find
}

# fd-find и bat на Debian/Ubuntu ставят бинарники под именами fdfind и
# batcat (конфликт имён с другими пакетами) — добавляем симлинки в
# /usr/local/bin, чтобы `fd`/`bat` работали напрямую (не только через
# алиас `cat`, см. modules/aliases.sh).
cli::ensure_symlinks() {
  if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    echo "cli-tools: символическая ссылка fd -> $(command -v fdfind)"
  fi
  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
    echo "cli-tools: символическая ссылка bat -> $(command -v batcat)"
  fi
}

cli::write_bat_config() {
  local src dest dest_dir
  src="$(cli::_dotfiles_dir)/config/bat.conf"
  dest_dir="$HOME/.config/bat"
  dest="$dest_dir/config"

  mkdir -p "$dest_dir"

  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    echo "cli-tools: существующий $dest отличается — делаю бэкап в $backup"
    cp "$dest" "$backup"
  fi

  cp "$src" "$dest"
  echo "cli-tools: $dest обновлён"
}

cli::install() {
  cli::install_pkg_group
  cli::ensure_symlinks
  cli::install_eza
  cli::install_delta
  cli::install_curlie
  cli::install_zoxide
  cli::write_bat_config
  echo "cli-tools: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/cli-tools.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
