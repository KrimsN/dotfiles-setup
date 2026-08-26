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

# Список объявлен константой (как CLI_PACKAGES в cli-tools.sh и
# DIAGNOSTICS_PACKAGES в diagnostics.sh) — его читает не только
# установка, но и `knrc uninstall`, чтобы знать, что именно этот модуль
# принёс на машину.
EXTRAS_PACKAGES=(tldr fastfetch)

extras::install() {
  local pkg
  for pkg in "${EXTRAS_PACKAGES[@]}"; do
    pkg::install "$pkg" || true
  done
  log::info "extras: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/extras.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
