#!/usr/bin/env bash
# Определение дистрибутива и пакетного менеджера.
# Не запускать напрямую — подключать через `source`.
#
# После source::os_detect() доступны переменные:
#   OS_ID           — id из /etc/os-release (ubuntu, debian, fedora, centos, rhel...)
#   OS_VERSION_ID    — версия дистрибутива (например 22.04, 39, 9)
#   OS_FAMILY        — debian | rhel
#   PKG_MANAGER      — apt | dnf | yum
#
# И функции-обёртки:
#   os::pkg_update              — обновить индекс пакетов
#   os::pkg_install <pkg...>    — установить пакеты

set -euo pipefail

os::detect() {
  if [ ! -r /etc/os-release ]; then
    echo "os-detect: /etc/os-release не найден — неподдерживаемая система" >&2
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"
  local id_like="${ID_LIKE:-}"

  case "$OS_ID" in
    ubuntu|debian)
      OS_FAMILY="debian"
      ;;
    fedora)
      OS_FAMILY="rhel"
      ;;
    centos|rhel|rocky|almalinux)
      OS_FAMILY="rhel"
      ;;
    *)
      # ID не распознан напрямую — пробуем ID_LIKE (частый случай для
      # производных дистрибутивов)
      case "$id_like" in
        *debian*) OS_FAMILY="debian" ;;
        *rhel*|*fedora*) OS_FAMILY="rhel" ;;
        *)
          echo "os-detect: неподдерживаемый дистрибутив: ID='$OS_ID' ID_LIKE='$id_like'" >&2
          echo "os-detect: поддерживаются Ubuntu, Debian, Fedora, CentOS" >&2
          return 1
          ;;
      esac
      ;;
  esac

  if [ "$OS_FAMILY" = "debian" ]; then
    PKG_MANAGER="apt"
  else
    # dnf вытеснил yum начиная с CentOS 8 / RHEL 8; на более старых
    # системах доступен только yum. Смотрим на реально установленный
    # бинарник, а не гадаем по версии.
    if command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
      PKG_MANAGER="yum"
    else
      echo "os-detect: не найден ни dnf, ни yum на системе семейства rhel" >&2
      return 1
    fi
  fi

  export OS_ID OS_VERSION_ID OS_FAMILY PKG_MANAGER
}

os::pkg_update() {
  case "$PKG_MANAGER" in
    apt) sudo apt-get update -y ;;
    dnf) sudo dnf makecache -y ;;
    yum) sudo yum makecache -y ;;
    *)
      echo "os::pkg_update: PKG_MANAGER не задан — вызови os::detect первым" >&2
      return 1
      ;;
  esac
}

os::pkg_install() {
  if [ "$#" -eq 0 ]; then
    echo "os::pkg_install: не переданы пакеты" >&2
    return 1
  fi
  case "$PKG_MANAGER" in
    apt) sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    yum) sudo yum install -y "$@" ;;
    *)
      echo "os::pkg_install: PKG_MANAGER не задан — вызови os::detect первым" >&2
      return 1
      ;;
  esac
}

# Если скрипт запущен напрямую (а не через source) — просто печатаем
# результат детекции. Удобно для быстрой проверки: ./os-detect.sh
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  os::detect
  echo "OS_ID=$OS_ID"
  echo "OS_VERSION_ID=$OS_VERSION_ID"
  echo "OS_FAMILY=$OS_FAMILY"
  echo "PKG_MANAGER=$PKG_MANAGER"
fi
