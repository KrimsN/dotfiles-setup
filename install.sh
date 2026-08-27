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
# Помимо модулей install.sh всегда ставит команду `knrc`
# (~/.local/bin/knrc, см. install_sh::_install_launcher) — точку входа
# для диагностики и будущих операций над уже настроенной машиной:
# `knrc doctor`.
#
# Модуль zsh-terminal-app НЕ входит в KNRC_ALL_MODULES и не предлагается ни
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

# Собственная копия root-safe sudo (канонический вариант —
# scripts/lib/os-detect.sh, переопределяет эту же функцию после того,
# как репозиторий склонирован, см. install_sh::main) — нужна здесь по
# той же причине, что и дублирование log::* выше: install_sh::_bootstrap_git_curl
# зовёт sudo до того, как os-detect.sh можно подключить через source.
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

# Единая точка выхода из интерактивных вопросов: по 'q' в меню, по
# Ctrl+C (см. `trap ... INT` в install_sh::main) и по EOF/закрытому
# /dev/tty на read. 130 — стандартный код завершения "прервано
# SIGINT", используем его и для явного 'q', чтобы код возврата был
# однозначным сигналом "пользователь отменил", а не ошибкой скрипта.
install_sh::_abort() {
  echo "" >&2
  log::err "install: отменено пользователем"
  exit 130
}

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
# Список модулей (KNRC_ALL_MODULES) приходит из scripts/lib/modules.sh —
# его подключает install_sh::main после того, как репозиторий на месте.
# Здесь его определить нельзя: при `curl | bash` репозитория ещё нет.

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
    echo "${KNRC_ALL_MODULES[*]}"
    return 0
  fi

  echo "" >&2
  log::prompt "Что установить?" >&2
  echo "" >&2
  log::prompt "  1) Всё (рекомендуется)" >&2
  echo "" >&2
  log::prompt "  2) Выбрать вручную" >&2
  echo "" >&2
  log::prompt "  3) Только команду knrc, без модулей" >&2
  echo "" >&2
  log::prompt "  q) Выйти" >&2
  echo "" >&2
  local choice
  read -r -p "$(log::prompt 'Выбор [1]: ')" choice < /dev/tty || install_sh::_abort
  choice="${choice:-1}"

  case "$choice" in
    q|Q) install_sh::_abort ;;
  esac

  if [ "$choice" = "3" ]; then
    echo ""
    return 0
  fi

  if [ "$choice" != "2" ]; then
    echo "${KNRC_ALL_MODULES[*]}"
    return 0
  fi

  local selected=() answer m i=1
  for m in "${KNRC_ALL_MODULES[@]}"; do
    read -r -p "$(log::prompt "  [$i/${#KNRC_ALL_MODULES[@]}] Установить '$m'? [Y/n/q] ")" answer < /dev/tty || install_sh::_abort
    case "$answer" in
      q|Q) install_sh::_abort ;;
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

# Ставит команду `knrc` в ~/.local/bin — тонкий шим, вся логика остаётся
# в репозитории (scripts/knrc.sh). Отсюда два следствия, ради которых
# схема и выбрана: обновление CLI = `git pull` в каталоге репозитория
# (шим переписывать не нужно), а sudo не требуется вовсе.
# Не модуль, а часть ядра установки: команда `knrc doctor` должна быть на
# машине независимо от того, какой набор модулей выбрал пользователь.
install_sh::_install_launcher() {
  local repo_dir="$1"
  local launcher="$HOME/.local/bin/knrc"

  localbin::ensure_path

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы лаунчер $launcher -> $repo_dir/scripts/knrc.sh"
    return 0
  fi

  cat > "$launcher" <<EOF
#!/usr/bin/env bash
# Managed by .knrc — лаунчер команды knrc, ставится install.sh
# (install_sh::_install_launcher). Правки здесь бессмысленны: файл
# перезаписывается при каждом запуске install.sh, а сама логика лежит
# в репозитории, на который он ссылается.
set -euo pipefail
KNRC_REPO_DIR="\${KNRC_REPO_DIR:-$repo_dir}"
if [ ! -f "\$KNRC_REPO_DIR/scripts/knrc.sh" ]; then
  echo "knrc: репозиторий не найден в \$KNRC_REPO_DIR — переустановите .knrc" >&2
  exit 1
fi
exec bash "\$KNRC_REPO_DIR/scripts/knrc.sh" "\$@"
EOF
  chmod +x "$launcher"
  log::info "install: команда 'knrc' установлена ($launcher -> $repo_dir)"
}

install_sh::main() {
  install_sh::_banner
  trap install_sh::_write_log EXIT
  trap install_sh::_abort INT

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
  source "$repo_dir/scripts/lib/backup.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/pkg-registry.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/localbin.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/modules.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/scripts/lib/state.sh"

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

  install_sh::_install_launcher "$repo_dir"

  local modules
  modules="$(install_sh::_selected_modules)"
  export DOTFILES_SELECTED_MODULES="$modules"
  echo ""
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::warn "install: РЕЖИМ DRY-RUN — изменений на диске/в системе не будет"
  fi
  if [ -z "$modules" ]; then
    log::info "install: модули не выбраны, ставлю только команду knrc"
  else
    log::info "install: устанавливаю: $modules"
  fi

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

  if [ -z "$modules" ]; then
    log::info "Готово! Команда knrc установлена, модули не ставились."
    log::info "Доступные команды:"
    echo ""
    bash "$repo_dir/scripts/knrc.sh" help
    echo ""

    if [ ! -r /dev/tty ]; then
      log::info "Перелогинься (или выполни 'source ~/.bashrc'), чтобы 'knrc' нашёлся в PATH."
      return 0
    fi

    local reopen
    read -r -p "$(log::prompt 'Открыть новый shell, чтобы knrc сразу заработал в PATH? [Y/n] ')" reopen < /dev/tty || true
    case "$reopen" in
      n|N|no|No)
        log::info "Ок. Выполни 'source ~/.bashrc' или перелогинься, чтобы 'knrc' нашёлся в PATH."
        return 0
        ;;
    esac

    # exec заменяет процесс install.sh, поэтому обычный EXIT-трап
    # (install_sh::_write_log) не сработает — пишем строку лога вручную
    # перед заменой. Новый shell читает ~/.bashrc с уже обновлённым PATH.
    true
    install_sh::_write_log
    trap - EXIT
    exec "${SHELL:-bash}" -l < /dev/tty
  fi

  log::info "Готово! Перелогинься (или открой новый терминал), чтобы изменения shell/группы docker применились."
  echo ""
  log::info "Проверить состояние машины в любой момент: knrc doctor"
  echo ""
  log::info "Настройка темы Powerlevel10k запустится автоматически при первом"
  log::info "интерактивном запуске zsh. Чтобы перезапустить мастер настройки"
  log::info "вручную в любой момент, выполни: p10k configure"
}

install_sh::main "$@"
