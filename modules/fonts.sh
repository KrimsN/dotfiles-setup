#!/usr/bin/env bash
# Установка Nerd Font-шрифтов для Powerlevel10k: JetBrainsMono Nerd
# Font, FiraCode Nerd Font (зафиксировано пользователем).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужен os::pkg_install для unzip/fontconfig,
# если их ещё нет).
#
# Публичная точка входа: fonts::install
#
# ВАЖНО: этот модуль ставит только файлы шрифта в
# ~/.local/share/fonts и обновляет кэш fontconfig — этого достаточно,
# чтобы шрифт стал виден системе. Но какой шрифт использовать в
# конкретном терминальном эмуляторе (GNOME Terminal, Konsole, iTerm2,
# Windows Terminal и т.д.) — настройка форматов у каждого своя,
# автоматизировать единым способом нельзя. Это пользователь выбирает
# вручную один раз в настройках своего терминала.

set -euo pipefail

FONTS_DIR="$HOME/.local/share/fonts"

# fonts::_install_one <человекочитаемое имя для сообщений> <имя ассета в nerd-fonts>
fonts::_install_one() {
  local label="$1" asset="$2"
  local dest="$FONTS_DIR/${asset}NerdFont"

  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    log::info "fonts: $label уже установлен, пропускаю"
    return 0
  fi

  local url
  url="$(curl -fsSL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
    | cut -d'"' -f4 \
    | grep -E "/${asset}\.zip$" | head -n1)"

  if [ -z "$url" ]; then
    log::err "fonts: не удалось найти релиз для $label (asset=$asset)"
    return 1
  fi

  local tmp
  tmp="$(mktemp -d)"
  log::info "fonts: скачиваю $label: $url"
  curl -fsSL "$url" -o "$tmp/font.zip"
  mkdir -p "$dest"
  unzip -q -o "$tmp/font.zip" -d "$dest"
  # В архиве кроме шрифтов лежат README/LICENSE — не нужны системе шрифтов.
  find "$dest" -type f ! \( -iname '*.ttf' -o -iname '*.otf' \) -delete
  rm -rf "$tmp"
  log::info "fonts: $label установлен в $dest"
}

fonts::install() {
  os::pkg_install unzip fontconfig

  fonts::_install_one "JetBrainsMono Nerd Font" "JetBrainsMono"
  fonts::_install_one "FiraCode Nerd Font" "FiraCode"

  log::info "fonts: обновляю кэш шрифтов"
  fc-cache -f "$FONTS_DIR" >/dev/null

  log::info "fonts: готово. Осталось выбрать 'JetBrainsMono Nerd Font' или 'FiraCode Nerd Font' в настройках шрифта твоего терминала вручную — это единственный шаг, который скрипт сделать не может."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/fonts.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
