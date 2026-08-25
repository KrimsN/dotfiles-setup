#!/usr/bin/env bash
# Установка "прочего" из списка программ: tldr, fastfetch.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/pkg-registry.sh (нужен pkg::install).
#
# Публичная точка входа: extras::install
#
# Способ установки каждого пакета — декларативно в
# data/packages/registry.json, через общий диспетчер pkg::install (см.
# scripts/lib/pkg-registry.sh, docs/design/pkg-metadata-json.md).
#
# neofetch (изначальный выбор) archived апстримом и убран из
# репозиториев Fedora — заменён на fastfetch (активно поддерживаемый
# форк, похожий вывод/конфиг), решение пользователя — сама техническая
# деталь установки (нет в репах Debian/Ubuntu, единообразно бинарником
# с GitHub Releases) теперь в реестре, не здесь.

set -euo pipefail

extras::install() {
  pkg::install tldr || true
  pkg::install fastfetch || true
  log::info "extras: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/extras.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
