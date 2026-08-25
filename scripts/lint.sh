#!/usr/bin/env bash
# Syntax-check every shell script in the project. Run before committing.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILED=0

while IFS= read -r -d '' file; do
  if ! bash -n "$file"; then
    echo "SYNTAX ERROR: $file" >&2
    FAILED=1
  fi
done < <(find . -name '*.sh' -not -path './.git/*' -print0)

if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r -d '' file; do
    shellcheck "$file" || FAILED=1
  done < <(find . -name '*.sh' -not -path './.git/*' -print0)
else
  echo "note: shellcheck not installed, skipping style checks (bash -n syntax check still ran)" >&2
fi

if [ "$FAILED" -eq 0 ]; then
  echo "OK: all scripts passed"
else
  echo "FAILED: see errors above" >&2
fi
exit "$FAILED"
