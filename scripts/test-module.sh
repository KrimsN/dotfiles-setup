#!/usr/bin/env bash
# Run one or more dotfiles-setup modules inside a disposable Docker
# container for a given distro, twice, to check idempotency.
#
# Usage:
#   scripts/test-module.sh <module>[,<module>...] <distro> [--once]
#
# <distro> is one of: ubuntu24 debian12 fedora centos9 centos7
# --once skips the second (idempotency) run.
set -euo pipefail

usage() {
  echo "Usage: $0 <module>[,<module>...] <distro> [--once]" >&2
  echo "  distro: ubuntu24 | debian12 | fedora | centos9 | centos7" >&2
  exit 1
}

[ $# -ge 2 ] || usage

MODULES="$1"
DISTRO="$2"
RUN_TWICE=1
[ "${3:-}" = "--once" ] && RUN_TWICE=0

case "$DISTRO" in
  ubuntu24) IMAGE="ubuntu:24.04" ;;
  debian12) IMAGE="debian:12" ;;
  fedora)   IMAGE="fedora:latest" ;;
  centos9)  IMAGE="quay.io/centos/centos:stream9" ;;
  centos7)  IMAGE="centos:7" ;;
  *) echo "Unknown distro: $DISTRO" >&2; usage ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Both runs happen inside a single container so the second run sees the
# state the first one left behind — that's what makes it an idempotency
# check rather than two independent fresh installs.
RUNS=1
[ $RUN_TWICE -eq 1 ] && RUNS=2

echo "== Testing modules [$MODULES] on $DISTRO ($IMAGE), $RUNS run(s) =="

docker run --rm \
  -v "$REPO_ROOT:/repo:ro" \
  -e "DOTFILES_MODULES=$MODULES" \
  -e NONINTERACTIVE=1 \
  -e "RUNS=$RUNS" \
  "$IMAGE" \
  bash -c '
    set -e
    cp -r /repo /tmp/dotfiles-setup
    cd /tmp/dotfiles-setup
    for i in $(seq 1 "$RUNS"); do
      echo "--- run $i/$RUNS ---"
      ./install.sh
    done
  '

echo "== OK: [$MODULES] on $DISTRO =="
