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
#   os::pkg_upgrade             — обновить индекс + накатить обновления
#                                 установленных пакетов
#   os::pkg_install <pkg...>    — установить пакеты

set -euo pipefail

# root-safe обёртка над sudo: на минимальных образах (например
# Docker-контейнеры без systemd), запущенных от root, бинарника sudo
# часто нет — а он там и не нужен, root и так может всё. Переопределяет
# команду `sudo`, так что весь остальной код (os::pkg_install и т.п.,
# а также модули, которые вызывают `sudo ...` напрямую) работает без
# изменений что от root, что от обычного пользователя.
# Канонический вариант — здесь; install.sh держит свою копию для
# install_sh::_bootstrap_git_curl, которая выполняется до того, как
# репозиторий склонирован и эту функцию можно подключить через source
# (см. комментарий в install.sh рядом с дублированием log::info/warn/err).
sudo() {
  if [ "$EUID" -eq 0 ]; then
    "$@"
    return
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    log::err "sudo не найден. Поставьте sudo от root (apt/dnf/yum install sudo) либо запустите install.sh от root."
    return 1
  fi
  command sudo "$@"
}

os::detect() {
  if [ ! -r /etc/os-release ]; then
    log::err "os-detect: /etc/os-release не найден — неподдерживаемая система"
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
          log::err "os-detect: неподдерживаемый дистрибутив: ID='$OS_ID' ID_LIKE='$id_like'"
          log::err "os-detect: поддерживаются Ubuntu, Debian, Fedora, CentOS"
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
      log::err "os-detect: не найден ни dnf, ни yum на системе семейства rhel"
      return 1
    fi
  fi

  export OS_ID OS_VERSION_ID OS_FAMILY PKG_MANAGER
}

os::pkg_update() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] обновил бы индекс пакетов ($PKG_MANAGER)"
    return 0
  fi
  case "$PKG_MANAGER" in
    apt) sudo apt-get update -y ;;
    dnf) sudo dnf makecache -y ;;
    yum) sudo yum makecache -y ;;
    *)
      log::err "os::pkg_update: PKG_MANAGER не задан — вызови os::detect первым"
      return 1
      ;;
  esac
}

os::pkg_upgrade() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] обновил бы индекс и накатил обновления пакетов ($PKG_MANAGER)"
    return 0
  fi
  case "$PKG_MANAGER" in
    apt)
      sudo apt-get update -y
      sudo apt-get upgrade -y
      ;;
    dnf) sudo dnf upgrade -y ;;
    yum) sudo yum update -y ;;
    *)
      log::err "os::pkg_upgrade: PKG_MANAGER не задан — вызови os::detect первым"
      return 1
      ;;
  esac
}

os::pkg_install() {
  if [ "$#" -eq 0 ]; then
    log::err "os::pkg_install: не переданы пакеты"
    return 1
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы пакеты ($PKG_MANAGER): $*"
    return 0
  fi
  case "$PKG_MANAGER" in
    apt) sudo apt-get install -y "$@" ;;
    # --allowerasing: минимальные образы (CentOS Stream/RHEL minimal)
    # ставят curl-minimal вместо curl, и обычный `dnf install curl`
    # падает на конфликте пакетов — просим dnf заменить его сам.
    dnf) sudo dnf install -y --allowerasing "$@" ;;
    yum) sudo yum install -y "$@" ;;
    *)
      log::err "os::pkg_install: PKG_MANAGER не задан — вызови os::detect первым"
      return 1
      ;;
  esac
}

# os::pkg_try_install <pkg> — установить один пакет, не прерывая скрипт
# при неудаче (в отличие от os::pkg_install под `set -e`). Нужен там,
# где на неудачу пакетного менеджера (пакет переименован/отсутствует в
# кастомном/корпоративном репозитории) есть alternative-стратегия
# установки — см. cli::fallback в modules/cli-tools.sh. Возвращает код
# возврата пакетного менеджера — вызывать в условии (`if ... ; then`).
os::pkg_try_install() {
  if [ "$#" -ne 1 ]; then
    log::err "os::pkg_try_install: ожидается ровно один пакет"
    return 1
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы пакет ($PKG_MANAGER): $1"
    return 0
  fi
  case "$PKG_MANAGER" in
    apt) sudo apt-get install -y "$1" ;;
    dnf) sudo dnf install -y --allowerasing "$1" ;;
    yum) sudo yum install -y "$1" ;;
    *)
      log::err "os::pkg_try_install: PKG_MANAGER не задан — вызови os::detect первым"
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
