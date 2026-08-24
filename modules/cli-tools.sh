#!/usr/bin/env bash
# Установка CLI-инструментов нового поколения:
# ripgrep, fd, fzf, bat, eza, zoxide, delta, jq, httpie, curlie.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужны OS_FAMILY, os::pkg_install).
#
# Публичная точка входа: cli::install
#
# Стратегия установки:
#   - ripgrep, fd, fzf, bat, jq, httpie — через пакетный менеджер
#     (для rhel-семейства предварительно включаем EPEL, там живёт
#     большинство из них).
#   - eza, delta, curlie, zoxide — их нет (или нет везде/во всех
#     версиях) в стандартных репах целевых дистрибутивов, поэтому
#     ставим статическими musl-бинарниками напрямую с GitHub Releases
#     — одинаково для всех дистрибутивов, без ветвления по OS_FAMILY.

set -euo pipefail

cli::_arch_rust() {
  case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    aarch64|arm64) echo aarch64 ;;
    *) uname -m ;;
  esac
}

cli::_arch_go() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) uname -m ;;
  esac
}

# cli::_github_install <repo> <asset_regex> <inner_binary_glob> <target_name>
# Скачивает последний релиз с GitHub, ищет ассет по regex, распаковывает
# и кладёт найденный бинарник в /usr/local/bin/<target_name>.
cli::_github_install() {
  local repo="$1" asset_regex="$2" inner_glob="$3" target_name="$4"

  if command -v "$target_name" >/dev/null 2>&1; then
    echo "cli-tools: $target_name уже установлен, пропускаю"
    return 0
  fi

  local url
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
    | cut -d'"' -f4 \
    | grep -E "$asset_regex" | head -n1)"

  if [ -z "$url" ]; then
    echo "cli-tools: не удалось найти релиз для $target_name (repo=$repo, pattern=$asset_regex)" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp -d)"
  echo "cli-tools: скачиваю $target_name: $url"
  curl -fsSL "$url" -o "$tmp/asset.tar.gz"
  tar -xzf "$tmp/asset.tar.gz" -C "$tmp"

  local bin_path
  bin_path="$(find "$tmp" -type f -name "$inner_glob" | head -n1)"
  if [ -z "$bin_path" ]; then
    echo "cli-tools: бинарник '$inner_glob' не найден в архиве $target_name" >&2
    rm -rf "$tmp"
    return 1
  fi

  sudo install -m 0755 "$bin_path" "/usr/local/bin/$target_name"
  rm -rf "$tmp"
  echo "cli-tools: $target_name установлен в /usr/local/bin/$target_name"
}

cli::install_eza() {
  cli::_github_install "eza-community/eza" \
    "eza_$(cli::_arch_rust)-unknown-linux-musl\.tar\.gz$" "eza" "eza"
}

cli::install_delta() {
  cli::_github_install "dandavison/delta" \
    "delta-.*-$(cli::_arch_rust)-unknown-linux-musl\.tar\.gz$" "delta" "delta"
}

cli::install_curlie() {
  cli::_github_install "rs/curlie" \
    "curlie_.*_linux_$(cli::_arch_go)\.tar\.gz$" "curlie" "curlie"
}

cli::install_zoxide() {
  cli::_github_install "ajeetdsouza/zoxide" \
    "zoxide-.*-$(cli::_arch_rust)-unknown-linux-musl\.tar\.gz$" "zoxide" "zoxide"
}

cli::install_epel() {
  if [ "$OS_FAMILY" != "rhel" ]; then
    return 0
  fi
  if rpm -q epel-release >/dev/null 2>&1; then
    echo "cli-tools: EPEL уже включён, пропускаю"
    return 0
  fi
  echo "cli-tools: включаю EPEL"
  os::pkg_install epel-release \
    || { echo "cli-tools: не удалось установить epel-release, продолжаю без него" >&2; return 0; }

  # Часть пакетов EPEL (например httpie) зависит от пакетов из CRB
  # (CodeReady Builder) — на CentOS Stream он не включён по умолчанию.
  if command -v crb >/dev/null 2>&1; then
    echo "cli-tools: включаю репозиторий CRB"
    sudo crb enable || echo "cli-tools: не удалось включить CRB, продолжаю без него" >&2
  fi
}

cli::install_pkg_group() {
  cli::install_epel
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

cli::install() {
  cli::install_pkg_group
  cli::ensure_symlinks
  cli::install_eza
  cli::install_delta
  cli::install_curlie
  cli::install_zoxide
  echo "cli-tools: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/cli-tools.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
