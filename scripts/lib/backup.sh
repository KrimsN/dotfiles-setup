#!/usr/bin/env bash
# Бэкап файла перед перезаписью новой версией из репозитория. Единая
# схема имени для всех модулей: <путь>.bak.<YYYYMMDDHHMMSS> —
# uninstall::_backups (scripts/uninstall.sh) находит бэкапы именно по
# этому глобу, и лексикографический порядок должен совпадать с
# хронологическим. Модуль, реализующий бэкап сам по себе (а не через
# эту функцию), молча выпадает из отката при малейшем расхождении в
# схеме имени.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh.

set -euo pipefail

# backup::create_if_diff <src> <dest> <label> — если $dest существует и
# отличается от $src, делает бэкап $dest рядом с ним и предупреждает
# через log::warn с префиксом label. Саму перезапись $dest не делает —
# это остаётся на вызывающей стороне.
backup::create_if_diff() {
  local src="$1" dest="$2" label="$3"
  local backup

  [ -f "$dest" ] || return 0
  cmp -s "$src" "$dest" && return 0

  backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
  log::warn "${label}: существующий $dest отличается — делаю бэкап в $backup"
  cp "$dest" "$backup"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/backup.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
