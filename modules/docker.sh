#!/usr/bin/env bash
# Установка Docker (docker engine + compose plugin — входит в
# современный docker, отдельно не ставится).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужен OS_ID для официального скрипта,
# хотя он и сам умеет определять дистрибутив).
#
# Публичная точка входа: docker::install
#
# Добавление пользователя в группу docker (запуск без sudo) —
# управляется механизмом конфигурации проекта (см. CLAUDE.md
# "Механизм конфигурации"): интерактивный вопрос через /dev/tty,
# env-override DOCKER_ADD_USER_TO_GROUP=yes|no, безопасный дефолт "no"
# без интерактива (группа docker по сути эквивалентна root).

set -euo pipefail

docker::install_engine() {
  if command -v docker >/dev/null 2>&1; then
    log::info "docker: уже установлен, пропускаю"
    return 0
  fi
  log::info "docker: устанавливаю через официальный скрипт get.docker.com"
  local script
  script="$(mktemp)"
  curl -fsSL https://get.docker.com -o "$script"
  sudo sh "$script"
  rm -f "$script"
}

docker::enable_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log::warn "docker: systemctl недоступен (нет systemd — контейнер/WSL без него?), пропускаю автозапуск"
    return 0
  fi
  log::info "docker: включаю и запускаю сервис"
  sudo systemctl enable --now docker \
    || log::warn "docker: не удалось включить сервис через systemctl, пропускаю"
}

# Спрашивает (или берёт из env/дефолта), нужно ли добавлять текущего
# пользователя в группу docker. Возвращает 0 (да) или 1 (нет).
docker::_want_user_in_group() {
  if [ -n "${DOCKER_ADD_USER_TO_GROUP:-}" ]; then
    case "$DOCKER_ADD_USER_TO_GROUP" in
      yes|y|1|true) return 0 ;;
      *) return 1 ;;
    esac
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || [ ! -r /dev/tty ]; then
    # Безопасный дефолт: группа docker эквивалентна root, не добавляем
    # без явного согласия.
    return 1
  fi

  local answer
  read -r -p "$(log::prompt "docker: добавить $USER в группу docker (запуск без sudo)? [y/N] ")" answer < /dev/tty || return 1
  case "$answer" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

docker::configure_user_group() {
  if groups "$USER" | grep -qw docker; then
    log::info "docker: $USER уже в группе docker, пропускаю"
    return 0
  fi

  if docker::_want_user_in_group; then
    log::info "docker: добавляю $USER в группу docker"
    sudo usermod -aG docker "$USER"
    log::info "docker: изменения группы применятся после перелогина"
  else
    log::info "docker: оставляю без добавления в группу (команды docker — через sudo)"
  fi
}

docker::install() {
  docker::install_engine
  docker::enable_service
  docker::configure_user_group
  log::info "docker: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/docker.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
