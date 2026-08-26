#!/usr/bin/env bash
# Round-trip test for `knrc uninstall` in a disposable Docker container:
#
#   clean container -> snapshot -> install -> snapshot
#   -> uninstall --dry-run -> snapshot (must equal the post-install one)
#   -> uninstall --force -> snapshot (must equal the initial one)
#
# Usage:
#   scripts/test-uninstall.sh <distro> [<module>[,<module>...]]
#
# <distro> is one of: ubuntu24 debian12 fedora centos9 centos7
# Modules default to a set that exercises every kind of change install
# makes (copied configs with backups, rc-blocks, git keys, binaries in
# /usr/local/bin, ~/.local/bin, fonts) without the two slowest modules.
#
# The two diffs are printed, not asserted away: some difference is
# EXPECTED and documented in docs/modules/uninstall.md — packages stay
# installed on purpose, and *.local extension points belong to the user.
# The script fails only when install or uninstall itself fails; reading
# the diffs is the actual test.
set -euo pipefail

usage() {
  echo "Usage: $0 <distro> [<module>[,<module>...]]" >&2
  echo "  distro: ubuntu24 | debian12 | fedora | centos9 | centos7" >&2
  exit 1
}

[ $# -ge 1 ] || usage

DISTRO="$1"
MODULES="${2:-base zsh tmux aliases cli-tools git-config ssh-config python-tools extras diagnostics fonts}"
MODULES="${MODULES//,/ }"

case "$DISTRO" in
  ubuntu24) IMAGE="ubuntu:24.04" ;;
  debian12) IMAGE="debian:12" ;;
  fedora)   IMAGE="fedora:latest" ;;
  centos9)  IMAGE="quay.io/centos/centos:stream9" ;;
  centos7)  IMAGE="centos:7" ;;
  *) echo "Unknown distro: $DISTRO" >&2; usage ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== uninstall round-trip: [$MODULES] on $DISTRO ($IMAGE) =="

docker run --rm \
  -v "$REPO_ROOT:/repo:ro" \
  -e "DOTFILES_MODULES=$MODULES" \
  -e NONINTERACTIVE=1 \
  -e ZSH_DEFAULT_SHELL=yes \
  "$IMAGE" \
  bash -c '
    set -e
    # Те же две причины, что и в scripts/test-module.sh: официальные
    # минимальные образы не включают sudo, а модули зовут его безусловно.
    if ! command -v sudo >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y sudo diffutils
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y sudo diffutils
      elif command -v yum >/dev/null 2>&1; then
        yum install -y sudo diffutils
      fi
    fi

    snapshot() {
      {
        echo "== home =="
        find "$HOME" -maxdepth 4 | sort
        echo "== /usr/local/bin =="
        ls -1A /usr/local/bin 2>/dev/null | sort
        echo "== login-shell =="
        getent passwd "$(id -un)" | cut -d: -f7
        echo "== git config --global =="
        git config --global -l 2>/dev/null | sort
        echo "== bashrc =="
        cat "$HOME/.bashrc" 2>/dev/null
      } > "$1" 2>&1 || true
    }

    cp -r /repo /tmp/knrc
    cd /tmp/knrc

    # Файл, которого до установки не было (бэкапа не будет -> должен
    # быть удалён), и файл, который до установки БЫЛ и отличается
    # (бэкап будет -> должен быть восстановлен слово в слово).
    printf "# СВОЙ tmux.conf ДО установки\nset -g mouse off\n" > "$HOME/.tmux.conf"
    cp "$HOME/.tmux.conf" /tmp/tmux.conf.original

    snapshot /tmp/snap-0-before-install.txt

    echo "--- install ---"
    ./install.sh

    snapshot /tmp/snap-1-after-install.txt

    echo "--- uninstall --dry-run (ничего не должно измениться) ---"
    bash scripts/knrc.sh uninstall --dry-run

    snapshot /tmp/snap-2-after-dryrun.txt

    echo ""
    echo "=== ДИФФ 1: изменил ли что-нибудь --dry-run (обязан быть ПУСТЫМ) ==="
    if diff -u /tmp/snap-1-after-install.txt /tmp/snap-2-after-dryrun.txt; then
      echo "OK: dry-run ничего не изменил"
    else
      echo "ПРОВАЛ: dry-run изменил состояние машины" >&2
      exit 1
    fi

    echo ""
    echo "--- uninstall --force ---"
    bash scripts/knrc.sh uninstall --force

    snapshot /tmp/snap-3-after-uninstall.txt

    echo ""
    echo "=== ДИФФ 2: чистая машина vs после uninstall ==="
    echo "(различия ожидаемы: пакеты не удаляются, *.local остаются —"
    echo " см. docs/modules/uninstall.md)"
    diff -u /tmp/snap-0-before-install.txt /tmp/snap-3-after-uninstall.txt || true

    echo ""
    echo "=== ПРОВЕРКА: ~/.tmux.conf восстановлен из бэкапа дословно ==="
    if diff -u /tmp/tmux.conf.original "$HOME/.tmux.conf"; then
      echo "OK: пользовательский ~/.tmux.conf вернулся"
    else
      echo "ПРОВАЛ: ~/.tmux.conf не совпадает с тем, что было до установки" >&2
      exit 1
    fi
  '

echo "== OK: uninstall round-trip on $DISTRO =="
