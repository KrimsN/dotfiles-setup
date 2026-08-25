#!/usr/bin/env bash
# Канонический список модулей проекта. Единственное место, где он
# определён: install.sh (что ставить) и scripts/doctor.sh (что
# проверять) обязаны видеть один и тот же перечень — иначе новый модуль
# появляется в установке, но молча выпадает из диагностики.
# Не запускать напрямую — подключать через `source`.
#
# Порядок значим: это порядок установки в install.sh и порядок вывода
# в `knrc doctor`.
#
# modules/zsh-terminal-app.sh сюда НЕ входит намеренно — он
# опциональный и запускается только явно
# (DOTFILES_MODULES=zsh-terminal-app), см. install.sh.

set -euo pipefail

# shellcheck disable=SC2034 # используется теми, кто подключает этот файл
KNRC_ALL_MODULES=(base zsh tmux nvim aliases cli-tools git-ecosystem git-config ssh-config docker python-tools extras diagnostics fonts)

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/modules.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
