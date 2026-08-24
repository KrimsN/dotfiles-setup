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
#     epel::ensure, там живёт большинство из них). Если конкретный
#     пакет недоступен (например на машине подменены репозитории на
#     внутренние корпоративные без части пакетов) — ставится по
#     отдельности через os::pkg_try_install, и при ненулевом коде
#     возврата модуль сам переключается на fallback для этого пакета
#     (GitHub Releases или pip), не роняя установку остальных
#     инструментов. См. cli::fallback.
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

cli::fallback_ripgrep() {
  github_release::install "BurntSushi/ripgrep" \
    "ripgrep-.*-$(github_release::arch_rust)-unknown-linux-musl\.tar\.gz$" "rg" "rg"
}

cli::fallback_fd() {
  github_release::install "sharkdp/fd" \
    "fd-v.*-$(github_release::arch_rust)-unknown-linux-musl\.tar\.gz$" "fd" "fd"
}

cli::fallback_fzf() {
  github_release::install "junegunn/fzf" \
    "fzf-.*-linux_$(github_release::arch_go)\.tar\.gz$" "fzf" "fzf"
}

cli::fallback_bat() {
  github_release::install "sharkdp/bat" \
    "bat-v.*-$(github_release::arch_rust)-unknown-linux-musl\.tar\.gz$" "bat" "bat"
}

cli::fallback_jq() {
  # jq публикует голые бинарники (не архивы), inner_path_glob не нужен.
  github_release::install "jqlang/jq" "jq-linux-$(github_release::arch_go)$" "" "jq"
}

cli::fallback_httpie() {
  # У httpie нет статических бинарников на GitHub Releases (это
  # python-пакет) — ставим через pip как альтернативу пакетному
  # менеджеру.
  log::info "cli-tools: httpie недоступен через $PKG_MANAGER — ставлю через pip"
  command -v pip3 >/dev/null 2>&1 || os::pkg_install python3-pip
  pip3 install --user httpie
}

# cli::fallback <pkg> — резервная установка для одного пакета из
# cli::install_pkg_group, когда os::pkg_try_install вернул ненулевой
# код (пакета нет в текущих репозиториях, например на машине с
# подменёнными внутренними/корпоративными репозиториями).
cli::fallback() {
  case "$1" in
    ripgrep) cli::fallback_ripgrep ;;
    fd-find) cli::fallback_fd ;;
    fzf) cli::fallback_fzf ;;
    bat) cli::fallback_bat ;;
    jq) cli::fallback_jq ;;
    httpie) cli::fallback_httpie ;;
    *)
      log::err "cli-tools: нет fallback-стратегии для пакета '$1' — пропускаю"
      return 1
      ;;
  esac
}

cli::install_pkg_group() {
  epel::ensure
  log::info "cli-tools: устанавливаю ripgrep, fd, fzf, bat, jq, httpie через пакетный менеджер"
  local pkg
  for pkg in ripgrep fzf jq httpie bat fd-find; do
    if os::pkg_try_install "$pkg"; then
      log::info "cli-tools: $pkg установлен через $PKG_MANAGER"
    else
      log::warn "cli-tools: $pkg недоступен через $PKG_MANAGER — пробую fallback"
      cli::fallback "$pkg"
    fi
  done
}

# fd-find и bat на Debian/Ubuntu ставят бинарники под именами fdfind и
# batcat (конфликт имён с другими пакетами) — добавляем симлинки в
# /usr/local/bin, чтобы `fd`/`bat` работали напрямую (не только через
# алиас `cat`, см. modules/aliases.sh).
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

  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    log::warn "cli-tools: существующий $dest отличается — делаю бэкап в $backup"
    cp "$dest" "$backup"
  fi

  cp "$src" "$dest"
  log::info "cli-tools: $dest обновлён"
}

cli::install() {
  cli::install_pkg_group
  cli::ensure_symlinks
  cli::install_eza
  cli::install_delta
  cli::install_curlie
  cli::install_zoxide
  cli::write_bat_config
  log::info "cli-tools: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/cli-tools.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
