#!/usr/bin/env bash
# Установка базового набора программ:
# git, curl, wget, vim, neovim, htop, btop, tree, unzip, zip, diffutils.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh и scripts/lib/epel.sh (нужны OS_FAMILY,
# os::pkg_install, epel::ensure — neovim и btop на CentOS/RHEL живут
# только в EPEL).
#
# Публичная точка входа: base::install

set -euo pipefail

base::install() {
  epel::ensure
  echo "base: устанавливаю базовый набор пакетов"
  os::pkg_install git curl wget vim neovim htop btop tree unzip zip diffutils
  echo "base: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/base.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
