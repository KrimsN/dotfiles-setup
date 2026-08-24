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
#   DOTFILES_MODULES="base zsh" — установить только перечисленные
#                                 модули без интерактивного меню
#   DOTFILES_DIR=/path          — куда клонировать репозиторий при
#                                 запуске через curl | bash
#                                 (по умолчанию ~/.local/share/knrc)
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
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  LOG_CYAN=$'\033[1;36m'
  LOG_YELLOW=$'\033[1;33m'
  LOG_RED=$'\033[1;31m'
  LOG_RESET=$'\033[0m'
else
  LOG_CYAN="" LOG_YELLOW="" LOG_RED="" LOG_RESET=""
fi
log::info() { echo "${LOG_CYAN}▶ ${1}${LOG_RESET}"; }
log::warn() { echo "${LOG_YELLOW}⚠ ${1}${LOG_RESET}" >&2; }
log::err()  { echo "${LOG_RED}✖ ${1}${LOG_RESET}" >&2; }

REPO_URL="${DOTFILES_REPO_URL:-https://github.com/KrimsN/krimsnrc.git}"
DEFAULT_INSTALL_DIR="$HOME/.local/share/knrc"
ALL_MODULES=(base zsh tmux nvim aliases cli-tools git-ecosystem docker extras fonts)

for arg in "$@"; do
  case "$arg" in
    --yes) export NONINTERACTIVE=1 ;;
  esac
done

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
    log::info "install: обновляю существующий клон в $dest"
    git -C "$dest" pull --ff-only >&2
  else
    log::info "install: клонирую $REPO_URL в $dest"
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
  echo "Что установить?" >&2
  echo "  1) Всё (рекомендуется)" >&2
  echo "  2) Выбрать вручную" >&2
  local choice
  read -r -p "Выбор [1]: " choice < /dev/tty || choice=""
  choice="${choice:-1}"

  if [ "$choice" != "2" ]; then
    echo "${ALL_MODULES[*]}"
    return 0
  fi

  local selected=() answer m i=1
  for m in "${ALL_MODULES[@]}"; do
    read -r -p "  [$i/${#ALL_MODULES[@]}] Установить '$m'? [Y/n] " answer < /dev/tty || answer=""
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
    docker)         docker::install ;;
    extras)         extras::install ;;
    fonts)          fonts::install ;;
    zsh-terminal-app) zsh_terminal_app::install ;;
    *) log::warn "install: неизвестный модуль '$1', пропускаю" ;;
  esac
}

install_sh::main() {
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
  source "$repo_dir/modules/docker.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/extras.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/fonts.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/zsh-terminal-app.sh"

  local modules
  modules="$(install_sh::_selected_modules)"
  echo ""
  log::info "install: устанавливаю: $modules"

  local m
  for m in $modules; do
    echo ""
    log::info "=== $m ==="
    install_sh::_run_module "$m"
  done

  echo ""
  log::info "Готово! Перелогинься (или открой новый терминал), чтобы изменения shell/группы docker применились."
  echo ""
  log::info "Настройка темы Powerlevel10k запустится автоматически при первом"
  log::info "интерактивном запуске zsh. Чтобы перезапустить мастер настройки"
  log::info "вручную в любой момент, выполни: p10k configure"
}

install_sh::main "$@"
