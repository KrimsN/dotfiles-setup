#!/usr/bin/env bash
# Отдельный опциональный модуль: создаёт .desktop-приложение, которое
# запускает терминал сразу в zsh, и (только в GNOME) перевешивает
# глобальный хоткей Ctrl+T на его запуск.
#
# НЕ входит в ALL_MODULES в install.sh — запускается только явно:
#   DOTFILES_MODULES=zsh-terminal-app ./install.sh
#
# Смысл: если zsh поставлен модулем modules/zsh.sh, но НЕ стал
# login-shell'ом по умолчанию (ZSH_DEFAULT_SHELL=no / ответ "нет" на
# вопрос chsh), даёт быстрый способ открыть терминал сразу в zsh без
# смены login-shell.
#
# Не запускать напрямую — подключать через `source`.
#
# Публичная точка входа: zsh_terminal_app::install

set -euo pipefail

ZSH_TERMINAL_APP_DESKTOP_ID="zsh-terminal-app.desktop"
ZSH_TERMINAL_APP_DESKTOP_DIR="$HOME/.local/share/applications"
ZSH_TERMINAL_APP_DESKTOP_FILE="$ZSH_TERMINAL_APP_DESKTOP_DIR/$ZSH_TERMINAL_APP_DESKTOP_ID"

# У разных терминальных эмуляторов разный синтаксис передачи команды
# для выполнения — единого стандарта нет.
zsh_terminal_app::_exec_for() {
  local term="$1" zsh_path="$2"
  case "$term" in
    gnome-terminal|tilix) echo "$term -- $zsh_path" ;;
    *)                    echo "$term -e $zsh_path" ;;
  esac
}

# Определяет доступный терминальный эмулятор: сначала $TERMINAL (если
# задан и существует), затем перебор известных по приоритету.
zsh_terminal_app::_detect_terminal_cmd() {
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [ -n "${TERMINAL:-}" ] && command -v "$TERMINAL" >/dev/null 2>&1; then
    zsh_terminal_app::_exec_for "$TERMINAL" "$zsh_path"
    return 0
  fi

  local term
  for term in gnome-terminal konsole xfce4-terminal tilix alacritty kitty xterm; do
    if command -v "$term" >/dev/null 2>&1; then
      zsh_terminal_app::_exec_for "$term" "$zsh_path"
      return 0
    fi
  done

  return 1
}

zsh_terminal_app::_write_desktop_file() {
  local exec_cmd="$1"
  mkdir -p "$ZSH_TERMINAL_APP_DESKTOP_DIR"
  cat > "$ZSH_TERMINAL_APP_DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Zsh Terminal
Comment=Терминал сразу в zsh
Exec=$exec_cmd
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
EOF
  log::info "zsh-terminal-app: создан $ZSH_TERMINAL_APP_DESKTOP_FILE (Exec=$exec_cmd)"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$ZSH_TERMINAL_APP_DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
}

# Переназначает Ctrl+T на запуск приложения через gsettings
# custom-keybindings — работает только в GNOME (relocatable schema
# org.gnome.settings-daemon.plugins.media-keys.custom-keybinding).
# Best-effort и идемпотентно: ищет первый свободный слот customN,
# по пути пропускает уже настроенный на ту же команду.
zsh_terminal_app::_bind_hotkey_gnome() {
  local exec_cmd="$1"
  local base="org.gnome.settings-daemon.plugins.media-keys"
  local list_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"

  command -v gsettings >/dev/null 2>&1 || return 1

  local i=0 path cur_cmd
  while :; do
    path="${list_path}custom${i}/"
    cur_cmd="$(gsettings get "${base}.custom-keybinding:${path}" command 2>/dev/null || echo "")"
    if [ "$cur_cmd" = "'$exec_cmd'" ]; then
      log::info "zsh-terminal-app: хоткей уже настроен (custom${i}), пропускаю"
      return 0
    fi
    if [ -z "$cur_cmd" ] || [ "$cur_cmd" = "''" ]; then
      break
    fi
    i=$((i + 1))
  done

  local new_path="${list_path}custom${i}/"
  local existing new_list
  existing="$(gsettings get "$base" custom-keybindings)"
  if [ "$existing" = "@as []" ] || [ "$existing" = "[]" ]; then
    new_list="['${new_path}']"
  else
    new_list="${existing%]}, '${new_path}']"
  fi

  gsettings set "$base" custom-keybindings "$new_list"
  gsettings set "${base}.custom-keybinding:${new_path}" name "Zsh Terminal"
  gsettings set "${base}.custom-keybinding:${new_path}" command "$exec_cmd"
  gsettings set "${base}.custom-keybinding:${new_path}" binding "<Primary>t"

  log::info "zsh-terminal-app: Ctrl+T переназначен на запуск zsh-терминала (GNOME, custom${i})"
}

zsh_terminal_app::install() {
  if ! command -v zsh >/dev/null 2>&1; then
    log::err "zsh-terminal-app: zsh не установлен, сначала выполните модуль zsh"
    return 1
  fi

  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$current_shell" = "$zsh_path" ]; then
    log::info "zsh-terminal-app: zsh уже login-shell по умолчанию, отдельное приложение не нужно, пропускаю"
    return 0
  fi

  local exec_cmd
  if ! exec_cmd="$(zsh_terminal_app::_detect_terminal_cmd)"; then
    log::err "zsh-terminal-app: не найден ни один известный терминальный эмулятор, пропускаю"
    return 1
  fi

  zsh_terminal_app::_write_desktop_file "$exec_cmd"

  if [ "${XDG_CURRENT_DESKTOP:-}" != "${XDG_CURRENT_DESKTOP/GNOME/}" ]; then
    zsh_terminal_app::_bind_hotkey_gnome "$exec_cmd" || \
      log::warn "zsh-terminal-app: не удалось настроить хоткей через gsettings, настройте Ctrl+T на запуск '$exec_cmd' вручную"
  else
    log::info "zsh-terminal-app: автоматическое переназначение Ctrl+T поддержано только для GNOME (обнаружено: '${XDG_CURRENT_DESKTOP:-неизвестно}')."
    log::info "zsh-terminal-app: настройте хоткей вручную в настройках DE — команда: $exec_cmd"
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/zsh-terminal-app.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
