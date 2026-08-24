#!/usr/bin/env bash
# Установка и настройка zsh + oh-my-zsh + Powerlevel10k.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужны PKG_MANAGER и os::pkg_install).
#
# Публичная точка входа: zsh::install
#
# Управление режимом "shell по умолчанию" — через механизм конфигурации
# проекта (см. CLAUDE.md "Механизм конфигурации"):
#   - интерактивный вопрос через /dev/tty, если доступен;
#   - иначе — переменная окружения ZSH_DEFAULT_SHELL=yes|no;
#   - если ни то ни другое — безопасный дефолт "no" (shell не меняется).

set -euo pipefail

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

zsh::_clone_if_missing() {
  local repo="$1" dest="$2"
  if [ -d "$dest" ]; then
    echo "zsh: уже установлено, пропускаю: $dest"
  else
    git clone --depth=1 "$repo" "$dest"
  fi
}

zsh::install_package() {
  echo "zsh: устанавливаю пакет zsh"
  os::pkg_install zsh
}

zsh::install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "zsh: oh-my-zsh уже установлен, пропускаю"
    return 0
  fi
  echo "zsh: устанавливаю oh-my-zsh"
  # RUNZSH=no  — не переключаться в zsh сразу после установки
  # CHSH=no    — смену login-shell делаем сами в zsh::configure_shell
  # KEEP_ZSHRC=yes — не даём инсталлятору генерировать свой .zshrc,
  #                  дальше пишем свой (zsh::write_zshrc)
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

zsh::install_powerlevel10k() {
  zsh::_clone_if_missing \
    https://github.com/romkatv/powerlevel10k.git \
    "$ZSH_CUSTOM/themes/powerlevel10k"
}

zsh::install_plugins() {
  zsh::_clone_if_missing \
    https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  zsh::_clone_if_missing \
    https://github.com/zdharma-continuum/fast-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"
  zsh::_clone_if_missing \
    https://github.com/zsh-users/zsh-completions \
    "$ZSH_CUSTOM/plugins/zsh-completions"
}

zsh::write_zshrc() {
  local src="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/config/zshrc"
  local dest="$HOME/.zshrc"

  if [ -f "$dest" ] && [ "$(cat "$src")" != "$(cat "$dest")" ]; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    echo "zsh: существующий ~/.zshrc отличается — делаю бэкап в $backup"
    cp "$dest" "$backup"
  fi

  cp "$src" "$dest"
  echo "zsh: ~/.zshrc обновлён"
}

# Спрашивает (или берёт из env/дефолта), нужно ли делать zsh login-shell
# по умолчанию. Возвращает 0 (да) или 1 (нет) через return code.
zsh::_want_default_shell() {
  if [ -n "${ZSH_DEFAULT_SHELL:-}" ]; then
    case "$ZSH_DEFAULT_SHELL" in
      yes|y|1|true) return 0 ;;
      *) return 1 ;;
    esac
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || [ ! -r /dev/tty ]; then
    # Безопасный дефолт: не трогаем login-shell без явного согласия.
    return 1
  fi

  local answer
  read -r -p "zsh: сделать zsh shell'ом по умолчанию (chsh)? [y/N] " answer < /dev/tty || return 1
  case "$answer" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

zsh::configure_shell() {
  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  # $SHELL не обновляется до перелогина, поэтому смотрим на passwd
  # напрямую — иначе повторный запуск всегда считает shell не сменённым.
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"

  if [ "$current_shell" = "$zsh_path" ]; then
    echo "zsh: уже установлен как shell по умолчанию, пропускаю"
    return 0
  fi

  if zsh::_want_default_shell; then
    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
      echo "zsh: добавляю $zsh_path в /etc/shells"
      echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi
    echo "zsh: делаю zsh shell'ом по умолчанию для $USER"
    sudo chsh -s "$zsh_path" "$USER"
  else
    echo "zsh: оставляю текущий login-shell без изменений (zsh доступен как альтернативный: $zsh_path)"
  fi
}

zsh::install() {
  zsh::install_package
  zsh::install_oh_my_zsh
  zsh::install_powerlevel10k
  zsh::install_plugins
  zsh::write_zshrc
  zsh::configure_shell
  echo "zsh: готово. Настройка Powerlevel10k (мастер 'p10k configure') запустится при первом интерактивном запуске zsh."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/zsh.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
