#!/usr/bin/env bash
# Установка и настройка Neovim: конфиг + lazy.nvim + базовый набор
# плагинов (дерево файлов, статус-бар, нечёткий поиск, treesitter).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужен os::pkg_install для diffutils).
#
# Публичная точка входа: nvim::install
#
# Бинарник ставится с GitHub Releases, а не из пакетного менеджера —
# в репозиториях (особенно Ubuntu/Debian) neovim сильно устаревший
# (0.9.5), там ещё нет vim.uv (появился в 0.10), от которого зависит
# bootstrap lazy.nvim в config/nvim/init.lua. Из того же соображения
# это НЕ github_release::install (scripts/lib/github-release.sh): тот
# рассчитан на самодостаточный статический бинарник (eza/delta/curlie/
# zoxide), а релизный архив neovim — это дерево bin/+lib/+share/
# (рантайм-файлы в share/nvim/runtime нужны бинарнику в момент
# запуска), распаковывается целиком в /usr/local.
#
# LSP и автодополнение сознательно не включены (см. CLAUDE.md) — если
# понадобятся, это отдельный шаг (nvim-lspconfig + mason).

set -euo pipefail

nvim::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

nvim::_arch() {
  case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    aarch64|arm64) echo arm64 ;;
    *)
      log::err "nvim: неподдерживаемая архитектура $(uname -m)"
      return 1
      ;;
  esac
}

nvim::install_package() {
  if command -v nvim >/dev/null 2>&1; then
    log::info "nvim: уже установлен ($(command -v nvim)), пропускаю"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы nvim с GitHub Releases в /usr/local/bin/nvim"
    return 0
  fi

  local arch url tmp
  arch="$(nvim::_arch)"
  url="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
    | cut -d'"' -f4 \
    | grep -E "nvim-linux-${arch}\.tar\.gz$")"

  if [ -z "$url" ]; then
    log::err "nvim: не удалось найти релизный архив для архитектуры $arch"
    return 1
  fi

  tmp="$(mktemp -d)"
  log::info "nvim: скачиваю $url"
  curl -fsSL "$url" -o "$tmp/nvim.tar.gz"
  tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"

  local src_dir
  src_dir="$(find "$tmp" -maxdepth 1 -type d -name 'nvim-linux-*' | head -n1)"
  # bin/, lib/, share/ распаковываются поверх /usr/local — так бинарник
  # находит свой рантайм по относительному пути (../share/nvim/runtime)
  sudo cp -r "$src_dir"/. /usr/local/
  rm -rf "$tmp"
  log::info "nvim: установлен в /usr/local/bin/nvim ($("$(command -v nvim)" --version | head -n1))"
}

nvim::write_config() {
  local src dest dest_dir
  src="$(nvim::_dotfiles_dir)/config/nvim/init.lua"
  dest_dir="$HOME/.config/nvim"
  dest="$dest_dir/init.lua"

  # cmp — часть diffutils, та же логика, что и у tmux::write_config
  os::pkg_install diffutils >/dev/null

  mkdir -p "$dest_dir"

  backup::create_if_diff "$src" "$dest" "nvim"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] обновил бы $dest"
    return 0
  fi

  cp "$src" "$dest"
  log::info "nvim: ~/.config/nvim/init.lua обновлён"
}

nvim::install_plugins() {
  # nvim-treesitter компилирует парсеры через `:TSUpdate` — без cc/gcc
  # сборка падает с "No C compiler found" (поймано при тестировании).
  os::pkg_install gcc >/dev/null

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы плагины nvim через lazy.nvim"
    return 0
  fi

  log::info "nvim: устанавливаю плагины через lazy.nvim (headless)"
  nvim --headless "+Lazy! sync" +qa
}

nvim::install() {
  nvim::install_package
  nvim::write_config
  nvim::install_plugins
  log::info "nvim: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/nvim.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
