#!/usr/bin/env bash
# .knrc — единая точка входа.
#
# Быстрое развёртывание:
#   curl -fsSL https://raw.githubusercontent.com/KrimsN/krimsnrc/master/install.sh | bash
#
# Или из уже склонированного репозитория:
#   ./install.sh
#
# Опции (см. CLAUDE.md "Механизм конфигурации"):
#   --yes / NONINTERACTIVE=1   — не задавать вопросов, дефолты везде
#                                 безопасные (см. отдельные модули)
#   --dry-run / DRY_RUN=1       — ничего не менять на диске/в системе,
#                                 только показать, что было бы сделано
#                                 (пакеты, rc-блоки, бинарники с GitHub
#                                 Releases — см. DRY_RUN в scripts/lib/*)
#   DOTFILES_MODULES="base zsh" — установить только перечисленные
#                                 модули без интерактивного меню
#   DOTFILES_DIR=/path          — куда клонировать репозиторий при
#                                 запуске через curl | bash
#                                 (по умолчанию ~/.local/share/knrc)
#
# Каждый прогон дописывает одну строку в ~/.knrc.log (время, режим,
# список модулей, дистрибутив, результат) — см. install_sh::_write_log.
#
# Модуль zsh-terminal-app НЕ входит в ALL_MODULES и не предлагается ни
# в общей установке, ни в интерактивном меню — запускается только
# явно: DOTFILES_MODULES=zsh-terminal-app ./install.sh. Он создаёт
# приложение "терминал сразу в zsh" и хоткей для случая, когда zsh
# установлен, но не стал login-shell'ом по умолчанию (см.
# modules/zsh-terminal-app.sh).

set -euo pipefail

# Собственная копия log::info/warn/err (см. scripts/lib/log.sh) —
# нужна ДО того, как репозиторий склонирован (случай `curl | bash`,
# см. install_sh::_bootstrap_git_curl ниже), поэтому подключить
# scripts/lib/log.sh отсюда невозможно. Та же причина дублирования, что
# и у логики определения дистрибутива чуть ниже.
LOG_TAG="[.knrc]"
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  LOG_CYAN=$'\033[1;36m'
  LOG_YELLOW=$'\033[1;33m'
  LOG_RED=$'\033[1;31m'
  LOG_PURPLE=$'\033[1;35m'
  LOG_RESET=$'\033[0m'
else
  LOG_CYAN="" LOG_YELLOW="" LOG_RED="" LOG_PURPLE="" LOG_RESET=""
fi
log::info() { echo "${LOG_CYAN}${LOG_TAG} ▶ ${1}${LOG_RESET}"; }
log::warn() { echo "${LOG_YELLOW}${LOG_TAG} ⚠ ${1}${LOG_RESET}" >&2; }
log::err()  { echo "${LOG_RED}${LOG_TAG} ✖ ${1}${LOG_RESET}" >&2; }

# ASCII-баннер ".KNRC" — печатается один раз в начале установки, чтобы
# сразу было видно, какой скрипт выполняется (актуально для `curl | bash`,
# где лог начинается посреди чужого вывода curl). Обрамление считается по
# фактической длине строк (не хардкодится), чтобы рамка не разъехалась
# при правках самого ASCII-арта.
install_sh::_banner() {
  local art=(
    "    █████   ████            ███                          ██████   █████"
    "   ░░███   ███░            ░░░                          ░░██████ ░░███"
    "    ░███  ███    ████████  ████  █████████████    █████  ░███░███ ░███  ████████   ██████"
    "    ░███████    ░░███░░███░░███ ░░███░░███░░███  ███░░   ░███░░███░███ ░░███░░███ ███░░███"
    "    ░███░░███    ░███ ░░░  ░███  ░███ ░███ ░███ ░░█████  ░███ ░░██████  ░███ ░░░ ░███ ░░░"
    "    ░███ ░░███   ░███      ░███  ░███ ░███ ░███  ░░░░███ ░███  ░░█████  ░███     ░███  ███"
    " ██ █████ ░░████ █████     █████ █████░███ █████ ██████  █████  ░░█████ █████    ░░██████"
    "░░ ░░░░░   ░░░░ ░░░░░     ░░░░░ ░░░░░ ░░░ ░░░░░ ░░░░░░  ░░░░░    ░░░░░ ░░░░░      ░░░░░░"
  )
  local subtitle="unix-окружение в одну команду: zsh · tmux · nvim · p10k"

  local line max=0
  for line in "${art[@]}" "$subtitle"; do
    (( ${#line} > max )) && max=${#line}
  done

  local pad=2 inner border
  inner=$(( max + pad * 2 ))
  border=$(printf '═%.0s' $(seq 1 "$inner"))

  printf '%s' "$LOG_PURPLE"
  printf '╔%s╗\n' "$border"
  for line in "${art[@]}"; do
    printf '║%*s%s%*s║\n' "$pad" '' "$line" $(( max - ${#line} + pad )) ''
  done
  printf '║%*s║\n' "$inner" ''
  printf '║%*s%s%*s║\n' "$pad" '' "$subtitle" $(( max - ${#subtitle} + pad )) ''
  printf '╚%s╝\n' "$border"
  printf '%s' "$LOG_RESET"
  echo ""
}

REPO_URL="${DOTFILES_REPO_URL:-https://github.com/KrimsN/krimsnrc.git}"
DEFAULT_INSTALL_DIR="$HOME/.local/share/knrc"
ALL_MODULES=(base zsh tmux nvim aliases cli-tools git-ecosystem git-config ssh-config docker python-tools extras diagnostics fonts)

for arg in "$@"; do
  case "$arg" in
    --yes) export NONINTERACTIVE=1 ;;
    --dry-run) export DRY_RUN=1 ;;
  esac
done

RUN_LOG_FILE="$HOME/.knrc.log"

# Пишет одну строку в ~/.knrc.log с результатом прогона. Вызывается из
# EXIT-трапа (см. install_sh::main), поэтому должна быть защищена от
# ненайденных переменных (`set -u`) — трап может сработать до того, как
# os::detect/модули отработали (например при ошибке бутстрапа git/curl).
# Ошибка самой записи в лог (например HOME на read-only ФС) не должна
# ронять уже завершившийся скрипт — отсюда `|| true`.
install_sh::_write_log() {
  local code=$? mode="install" status="ok"
  [ "${DRY_RUN:-0}" = "1" ] && mode="dry-run"
  [ "$code" -ne 0 ] && status="fail(exit=$code)"
  {
    printf '%s mode=%s status=%s distro=%s modules="%s"\n' \
      "$(date +%Y-%m-%dT%H:%M:%S%z)" \
      "$mode" \
      "$status" \
      "${OS_ID:-?}${OS_VERSION_ID:+/$OS_VERSION_ID}" \
      "${DOTFILES_SELECTED_MODULES:-}"
  } >> "$RUN_LOG_FILE" 2>/dev/null || true
}

# При `curl | bash` у скрипта нет собственного пути на диске (stdin) —
# в этом случае репозиторий нужно клонировать, а для этого нужны git и
# curl, которых на свежей машине может ещё не быть. Это единственное
# место в проекте, где логика определения дистрибутива продублирована
# намеренно: остальной код репозитория (который мы бутстрапим) ещё не
# скачан, использовать scripts/lib/os-detect.sh неоткуда.
install_sh::_bootstrap_git_curl() {
  if command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    return 0
  fi

  log::warn "install: git/curl отсутствуют, ставлю для бутстрапа"

  local id="" id_like=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  # Весь вывод этих команд перенаправлен в stderr (не stdout) —
  # install_sh::_ensure_repo вызывает эту функцию внутри своего тела и
  # сама вызывается через command substitution `$(...)`; любой байт,
  # случайно попавший в stdout здесь, испортит захваченный путь к
  # репозиторию (реально ловили баг: вывод apt-get попадал в переменную
  # с путём — "File name too long" при попытке source этого "пути").
  {
    case "$id" in
      ubuntu|debian)
        sudo apt-get update -y
        sudo apt-get install -y git curl ca-certificates
        ;;
      fedora)
        sudo dnf install -y --allowerasing git curl
        ;;
      centos|rhel|rocky|almalinux)
        # --allowerasing: на CentOS Stream минимальные образы содержат
        # curl-minimal, который конфликтует с полным curl без этого
        # флага (реально ловили эту ошибку при тестировании).
        sudo dnf install -y --allowerasing git curl 2>/dev/null \
          || sudo yum install -y git curl
        ;;
      *)
        case "$id_like" in
          *debian*)
            sudo apt-get update -y
            sudo apt-get install -y git curl ca-certificates
            ;;
          *rhel*|*fedora*)
            sudo dnf install -y --allowerasing git curl 2>/dev/null \
              || sudo yum install -y git curl
            ;;
          *)
            log::err "install: не знаю как поставить git/curl на этой системе (ID='$id' ID_LIKE='$id_like')"
            exit 1
            ;;
        esac
        ;;
    esac
  } >&2
}

install_sh::_self_dir() {
  local src="${BASH_SOURCE[0]}"
  if [ -f "$src" ]; then
    (cd "$(dirname "$src")" && pwd)
  fi
}

# Возвращает путь к каталогу репозитория (существующий локальный клон,
# либо только что склонированный/обновлённый).
install_sh::_ensure_repo() {
  local self_dir
  self_dir="$(install_sh::_self_dir || true)"

  if [ -n "$self_dir" ] && [ -d "$self_dir/modules" ]; then
    echo "$self_dir"
    return 0
  fi

  install_sh::_bootstrap_git_curl

  local dest="${DOTFILES_DIR:-$DEFAULT_INSTALL_DIR}"
  if [ -d "$dest/.git" ]; then
    log::info "install: обновляю существующий клон в $dest" >&2
    git -C "$dest" pull --ff-only >&2
  else
    log::info "install: клонирую $REPO_URL в $dest" >&2
    mkdir -p "$(dirname "$dest")"
    git clone --depth=1 "$REPO_URL" "$dest" >&2
  fi
  echo "$dest"
}

install_sh::_selected_modules() {
  if [ -n "${DOTFILES_MODULES:-}" ]; then
    echo "$DOTFILES_MODULES"
    return 0
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || [ ! -r /dev/tty ]; then
    echo "${ALL_MODULES[*]}"
    return 0
  fi

  echo "" >&2
  log::prompt "Что установить?" >&2
  echo "" >&2
  log::prompt "  1) Всё (рекомендуется)" >&2
  log::prompt "  2) Выбрать вручную" >&2
  local choice
  read -r -p "$(log::prompt 'Выбор [1]: ')" choice < /dev/tty || choice=""
  choice="${choice:-1}"

  if [ "$choice" != "2" ]; then
    echo "${ALL_MODULES[*]}"
    return 0
  fi

  local selected=() answer m i=1
  for m in "${ALL_MODULES[@]}"; do
    read -r -p "$(log::prompt "  [$i/${#ALL_MODULES[@]}] Установить '$m'? [Y/n] ")" answer < /dev/tty || answer=""
    case "$answer" in
      n|N|no|No) ;;
      *) selected+=("$m") ;;
    esac
    i=$((i + 1))
  done
  echo "${selected[*]}"
}

install_sh::_run_module() {
  case "$1" in
    base)           base::install ;;
    zsh)            zsh::install ;;
    tmux)           tmux::install ;;
    nvim)           nvim::install ;;
    aliases)        aliases::install ;;
    cli-tools)      cli::install ;;
    git-ecosystem)  git_eco::install ;;
    git-config)     git_config::install ;;
    ssh-config)     ssh_config::install ;;
    docker)         docker::install ;;
    python-tools)   python_tools::install ;;
    extras)         extras::install ;;
    diagnostics)    diagnostics::install ;;
    fonts)          fonts::install ;;
    zsh-terminal-app) zsh_terminal_app::install ;;
    *) log::warn "install: неизвестный модуль '$1', пропускаю" ;;
  esac
}

install_sh::main() {
  install_sh::_banner
  trap install_sh::_write_log EXIT

  local repo_dir
  repo_dir="$(install_sh::_ensure_repo)"
  export DOTFILES_DIR="$repo_dir"

  # log::info/warn/err уже определены выше (см. комментарий у REPO_URL) —
  # источник ниже лишь синхронизирует канонический вариант из репозитория,
  # чтобы модули, подключаемые напрямую (в обход install.sh, например при
  # разработке), тоже могли им пользоваться.
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/log.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/os-detect.sh"
  os::detect
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/epel.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/github-release.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/rcfile.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/pkg-registry.sh"

  # shellcheck disable=SC1091
  source "$repo_dir/modules/base.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/zsh.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/tmux.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/nvim.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/aliases.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/cli-tools.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/git-ecosystem.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/git-config.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/ssh-config.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/docker.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/python-tools.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/extras.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/diagnostics.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/fonts.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/zsh-terminal-app.sh"

  local modules
  modules="$(install_sh::_selected_modules)"
  export DOTFILES_SELECTED_MODULES="$modules"
  echo ""
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::warn "install: РЕЖИМ DRY-RUN — изменений на диске/в системе не будет"
  fi
  log::info "install: устанавливаю: $modules"

  local m
  for m in $modules; do
    echo ""
    log::info "=== $m ==="
    install_sh::_run_module "$m"
  done

  echo ""
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "Dry-run завершён, изменений не было. Для реальной установки запусти без --dry-run."
    return 0
  fi

  log::info "Готово! Перелогинься (или открой новый терминал), чтобы изменения shell/группы docker применились."
  echo ""
  log::info "Настройка темы Powerlevel10k запустится автоматически при первом"
  log::info "интерактивном запуске zsh. Чтобы перезапустить мастер настройки"
  log::info "вручную в любой момент, выполни: p10k configure"
}

install_sh::main "$@"
