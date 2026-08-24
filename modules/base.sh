#!/usr/bin/env bash
# Установка базового набора программ:
# git, curl, wget, vim, htop, btop, tree, unzip, zip, diffutils.
# (neovim сюда не входит — свежий бинарник ставится отдельным модулем
# modules/nvim.sh с GitHub Releases, пакетную версию из репозиториев
# не дублируем, см. CLAUDE.md.)
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh и scripts/lib/epel.sh (нужны OS_FAMILY,
# os::pkg_install, epel::ensure — btop на CentOS/RHEL живёт только в
# EPEL).
#
# Публичная точка входа: base::install

set -euo pipefail

base::install() {
  epel::ensure
  log::info "base: устанавливаю базовый набор пакетов"
  os::pkg_install git curl wget vim htop btop tree unzip zip diffutils
  log::info "base: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/base.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
