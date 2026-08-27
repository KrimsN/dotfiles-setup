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
#
# Под WSL тем же механизмом (интерактивный вопрос / env-override
# DOCKER_WSL_MODE=desktop|engine / дефолт "engine" без интерактива)
# выбирается между инструкцией по Docker Desktop и обычной установкой
# Docker Engine внутри дистрибутива — см. docker::_ask_wsl_mode.

set -euo pipefail

# На RHEL-семье (замечено на CentOS Stream в WSL) `/usr/bin/docker`
# нередко уже существует — но это не Docker Engine, а шим из пакета
# podman-docker (symlink либо обёртка, транслирующая docker-команды в
# podman). Голая проверка `command -v docker` принимала этот шим за
# "уже установлен" и пропускала установку — из-за чего дальше не было
# ни docker.service, ни группы docker (их создаёт постинсталл настоящего
# docker-ce, а не podman-docker).
docker::_is_podman_shim() {
  command -v docker >/dev/null 2>&1 || return 1
  local docker_bin
  docker_bin="$(command -v docker)"
  if readlink -f "$docker_bin" 2>/dev/null | grep -qi podman; then
    return 0
  fi
  docker --version 2>/dev/null | grep -qi podman
}

# get.docker.com сам детектит WSL и в этом случае просто предупреждает
# и ждёт 20 секунд перед тем, как продолжить обычную установку Docker
# Engine — из-за чего лог выглядит как будто скрипт завис. Свой выбор
# делаем до запуска официального скрипта: даём осознанно выбрать между
# Docker Desktop (ставится отдельно на Windows-хосте, внутри WSL только
# инструкция) и обычным Docker Engine внутри дистрибутива — тем же
# способом, что и раньше, но без сюрприза с паузой.
#
# Возвращает выбор через глобальную переменную docker_wsl_mode
# (desktop|engine) — не через stdout, чтобы не мешать
# command-substitution с выводом log::* (он тоже идёт в stdout).
docker::_ask_wsl_mode() {
  if [ -n "${DOCKER_WSL_MODE:-}" ]; then
    case "$DOCKER_WSL_MODE" in
      desktop) docker_wsl_mode="desktop"; return 0 ;;
      engine) docker_wsl_mode="engine"; return 0 ;;
      *)
        log::warn "docker: DOCKER_WSL_MODE='$DOCKER_WSL_MODE' не распознан (ожидается desktop|engine), игнорирую"
        ;;
    esac
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || [ ! -r /dev/tty ]; then
    # Безопасный дефолт без интерактива: ставим Docker Engine внутри
    # WSL — это и есть прежнее поведение скрипта до появления выбора.
    docker_wsl_mode="engine"
    return 0
  fi

  log::warn "docker: обнаружен WSL — Docker Desktop для Windows и Docker Engine внутри дистрибутива это два разных, взаимоисключающих способа получить docker в WSL"
  local answer
  read -r -p "$(log::prompt "docker: что ставим — Docker Desktop (инструкция, ставится на Windows) или Docker Engine (внутри WSL, как обычный Linux)? [engine/desktop, по умолчанию engine] ")" answer < /dev/tty || answer=""
  case "$answer" in
    desktop|Desktop|d|D) docker_wsl_mode="desktop" ;;
    *) docker_wsl_mode="engine" ;;
  esac
}

docker::_print_wsl_desktop_instructions() {
  log::info "docker: выбран Docker Desktop — сам он ставится на Windows, а не в WSL, поэтому этот шаг только печатает инструкцию:"
  log::info "  1. Скачайте и установите Docker Desktop на Windows: https://www.docker.com/products/docker-desktop/"
  log::info "  2. После установки откройте Docker Desktop → Settings → Resources → WSL Integration"
  log::info "  3. Включите интеграцию для этого дистрибутива (переключатель с его именем в списке)"
  log::info "  4. Перезапустите WSL, чтобы интеграция подхватилась: из Windows — 'wsl --shutdown', затем откройте терминал заново"
  log::info "  5. Проверьте внутри WSL: 'docker info' — команда должна отвечать без sudo и без локального docker.service"
}

docker::install_engine() {
  local is_shim=0
  if docker::_is_podman_shim; then
    is_shim=1
  elif command -v docker >/dev/null 2>&1; then
    log::info "docker: уже установлен, пропускаю"
    return 0
  fi

  if os::is_wsl; then
    local docker_wsl_mode
    docker::_ask_wsl_mode
    if [ "$docker_wsl_mode" = "desktop" ]; then
      docker::_print_wsl_desktop_instructions
      return 0
    fi
    log::info "docker: выбран Docker Engine внутри WSL — ставлю как на обычном Linux"
  fi

  if [ "$is_shim" = "1" ]; then
    log::warn "docker: найден podman-docker (docker — это шим от podman, не настоящий Docker Engine) — удаляю его, чтобы поставить настоящий"
    if [ "${DRY_RUN:-0}" = "1" ]; then
      log::info "[dry-run] удалил бы пакет podman-docker и установил бы docker через get.docker.com"
      return 0
    fi
    case "$PKG_MANAGER" in
      apt) sudo apt-get remove -y podman-docker ;;
      dnf) sudo dnf remove -y podman-docker ;;
      yum) sudo yum remove -y podman-docker ;;
      *)
        log::err "docker::install_engine: PKG_MANAGER не задан — вызови os::detect первым"
        return 1
        ;;
    esac
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
