#!/usr/bin/env bash
# Установка диагностических утилит: rsync, dig (dnsutils/bind-utils),
# ncdu, lsof, mtr. Не запускать напрямую — подключать через `source`
# после scripts/lib/pkg-registry.sh (нужен pkg::install).
#
# Публичная точка входа: diagnostics::install
#
# Добавлены по согласованию с пользователем (2026-08-25) — базовый
# список программ в CLAUDE.md не покрывал сетевую/файловую диагностику
# на свежей машине. Вынесены в отдельный модуль, а не в modules/base.sh:
# у dig и mtr имя пакета расходится между apt и dnf/yum (в отличие от
# всего остального в base.sh, где `os::pkg_install` ставит одинаковые
# имена одним вызовом) — это ровно та задача, для которой существует
# декларативный реестр data/packages/registry.json и диспетчер
# pkg::install, см. docs/design/pkg-metadata-json.md.
#
# Способ установки каждого пакета — декларативно в
# data/packages/registry.json, через общий диспетчер pkg::install (см.
# scripts/lib/pkg-registry.sh). pkg::install сам продолжает установку
# остальных пакетов, если для одного отвалились все способы (не роняет
# diagnostics::install) — см. `|| true` ниже.

set -euo pipefail

DIAGNOSTICS_PACKAGES=(rsync dig ncdu lsof mtr)

diagnostics::install() {
  local pkg
  for pkg in "${DIAGNOSTICS_PACKAGES[@]}"; do
    pkg::install "$pkg" || true
  done
  log::info "diagnostics: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/diagnostics.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
