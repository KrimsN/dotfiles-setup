#!/usr/bin/env bash
# Включение EPEL (+ CRB) на rhel-семействе. Часть пакетов, которые
# ставят разные модули (bat, ripgrep, neovim, btop и т.п.), на
# CentOS/RHEL живут только в EPEL, а часть пакетов EPEL требует
# зависимостей из CRB (CodeReady Builder), не включённого по умолчанию.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужны OS_FAMILY, os::pkg_install).

set -euo pipefail

epel::ensure() {
  if [ "$OS_FAMILY" != "rhel" ]; then
    return 0
  fi
  if rpm -q epel-release >/dev/null 2>&1; then
    log::info "epel: уже включён, пропускаю"
    return 0
  fi

  log::info "epel: включаю EPEL"
  os::pkg_install epel-release \
    || { log::warn "epel: не удалось установить epel-release, продолжаю без него"; return 0; }

  if command -v crb >/dev/null 2>&1; then
    log::info "epel: включаю репозиторий CRB"
    sudo crb enable || log::warn "epel: не удалось включить CRB, продолжаю без него"
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/epel.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
