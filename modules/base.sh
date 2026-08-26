#!/usr/bin/env bash
# Обновление репозиториев/пакетов системы (apt update + upgrade и
# аналоги для dnf/yum) и установка базового набора программ:
# git, curl, wget, vim, htop, btop, tree, unzip, zip, tar, diffutils.
# (neovim сюда не входит — свежий бинарник ставится отдельным модулем
# modules/nvim.sh с GitHub Releases, пакетную версию из репозиториев
# не дублируем, см. CLAUDE.md.)
#
# tar здесь не только пользовательская утилита: scripts/lib/github-release.sh
# (общая инфраструктура установки бинарников с GitHub Releases — её
# использует nvim.sh и часть пакетов из data/packages/registry.json)
# распаковывает .tar.gz-ассеты через `tar -xzf` без собственной
# проверки/установки, и на урезанных образах без tar падает.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh и scripts/lib/epel.sh (нужны OS_FAMILY,
# os::pkg_install, epel::ensure — btop на CentOS/RHEL живёт только в
# EPEL).
#
# Публичная точка входа: base::install

set -euo pipefail

base::install() {
  log::info "base: обновляю репозитории и пакеты системы"
  os::pkg_upgrade
  epel::ensure
  log::info "base: устанавливаю базовый набор пакетов"
  os::pkg_install git curl wget vim htop btop tree unzip zip tar diffutils
  log::info "base: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/base.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
