#!/usr/bin/env bash
# Установка Docker (docker engine + compose plugin — входит в
# современный docker, отдельно не ставится).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужен OS_ID для официального скрипта,
# хотя он и сам умеет определять дистрибутив) и scripts/lib/state.sh
# (нужен state::record).
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

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы docker через get.docker.com"
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

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] включил бы и запустил сервис docker"
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

  local answer current_user
  current_user="$(id -un)"
  read -r -p "$(log::prompt "docker: добавить $current_user в группу docker (запуск без sudo)? [y/N] ")" answer < /dev/tty || return 1
  case "$answer" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

docker::configure_user_group() {
  # $USER не гарантированно задана (например, в контейнерах CI) —
  # берём фактическое имя пользователя через id.
  local current_user
  current_user="$(id -un)"

  if groups "$current_user" | grep -qw docker; then
    log::info "docker: $current_user уже в группе docker, пропускаю"
    return 0
  fi

  if docker::_want_user_in_group; then
    if [ "${DRY_RUN:-0}" = "1" ]; then
      log::info "[dry-run] добавил бы $current_user в группу docker"
      return 0
    fi

    log::info "docker: добавляю $current_user в группу docker"
    # Записываем сам факт добавления: по `id -nG` потом видно только
    # "состоит в группе", а состоял ли он в ней до нас — уже нет.
    # `knrc uninstall` выводит из группы ТОЛЬКО по этой записи, см.
    # scripts/lib/state.sh.
    state::record "docker-group.added" "$current_user"
    sudo usermod -aG docker "$current_user"
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
