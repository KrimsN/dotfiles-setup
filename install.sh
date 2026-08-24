#!/usr/bin/env bash
# dotfiles-setup — единая точка входа.
#
# Быстрое развёртывание:
#   curl -fsSL https://raw.githubusercontent.com/KrimsN/dotfiles-setup/master/install.sh | bash
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
#                                 (по умолчанию ~/.local/share/dotfiles-setup)

set -euo pipefail

REPO_URL="${DOTFILES_REPO_URL:-https://github.com/KrimsN/dotfiles-setup.git}"
DEFAULT_INSTALL_DIR="$HOME/.local/share/dotfiles-setup"
ALL_MODULES=(base zsh tmux aliases cli-tools git-ecosystem docker extras)

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

  echo "install: git/curl отсутствуют, ставлю для бутстрапа" >&2

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
        sudo dnf install -y git curl
        ;;
      centos|rhel|rocky|almalinux)
        sudo dnf install -y git curl 2>/dev/null || sudo yum install -y git curl
        ;;
      *)
        case "$id_like" in
          *debian*)
            sudo apt-get update -y
            sudo apt-get install -y git curl ca-certificates
            ;;
          *rhel*|*fedora*)
            sudo dnf install -y git curl 2>/dev/null || sudo yum install -y git curl
            ;;
          *)
            echo "install: не знаю как поставить git/curl на этой системе (ID='$id' ID_LIKE='$id_like')" >&2
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
    echo "install: обновляю существующий клон в $dest" >&2
    git -C "$dest" pull --ff-only >&2
  else
    echo "install: клонирую $REPO_URL в $dest" >&2
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
    aliases)        aliases::install ;;
    cli-tools)      cli::install ;;
    git-ecosystem)  git_eco::install ;;
    docker)         docker::install ;;
    extras)         extras::install ;;
    *) echo "install: неизвестный модуль '$1', пропускаю" >&2 ;;
  esac
}

install_sh::main() {
  local repo_dir
  repo_dir="$(install_sh::_ensure_repo)"
  export DOTFILES_DIR="$repo_dir"

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
  source "$repo_dir/modules/aliases.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/cli-tools.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/git-ecosystem.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/docker.sh"
  # shellcheck disable=SC1091
  source "$repo_dir/modules/extras.sh"

  local modules
  modules="$(install_sh::_selected_modules)"
  echo ""
  echo "install: устанавливаю: $modules"

  local m
  for m in $modules; do
    echo ""
    echo "=== $m ==="
    install_sh::_run_module "$m"
  done

  echo ""
  echo "Готово! Перелогинься (или открой новый терминал), чтобы изменения shell/группы docker применились."
}

install_sh::main "$@"
