#!/usr/bin/env bash
# Идемпотентная вставка/обновление маркированного блока в rc-файл
# (~/.bashrc и т.п.), не затрагивая остальное содержимое файла.
# Не запускать напрямую — подключать через `source`.

set -euo pipefail

# rcfile::upsert_block <file> <marker> <content>
# marker — короткий идентификатор блока (например "tmux-autoattach"),
# используется только для маркерных комментариев, должен быть
# уникальным для каждого использования.
rcfile::upsert_block() {
  local file="$1" marker="$2" content="$3"
  local begin="# >>> knrc:${marker} >>>"
  local end="# <<< knrc:${marker} <<<"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] обновил бы блок '$marker' в $file"
    return 0
  fi

  touch "$file"

  if grep -qF "$begin" "$file"; then
    local existing
    existing="$(awk -v b="$begin" -v e="$end" '
      $0 == b { p=1; next } $0 == e { p=0; next } p { print }
    ' "$file")"

    if [ "$existing" = "$content" ]; then
      return 0
    fi

    local tmp
    tmp="$(mktemp)"
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip=1; next }
      $0 == end   { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  fi

  {
    echo ""
    echo "$begin"
    echo "$content"
    echo "$end"
  } >> "$file"
}

# rcfile::remove_block <file> <marker>
# Удаляет ранее вставленный блок, если он есть; отсутствие файла или
# самого блока — не ошибка (идемпотентно). Нужен при переименовании
# маркера (миграция уже установленных машин).
rcfile::remove_block() {
  local file="$1" marker="$2"
  local begin="# >>> knrc:${marker} >>>"
  local end="# <<< knrc:${marker} <<<"

  [ -f "$file" ] || return 0
  grep -qF "$begin" "$file" || return 0

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] удалил бы блок '$marker' из $file"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/rcfile.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
