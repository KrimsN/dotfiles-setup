#!/usr/bin/env bash
# ~/.local/bin в PATH: туда кладут бинарники и uv (`uv tool install`), и
# сам лаунчер `knrc` (см. install_sh::_install_launcher). Общая точка,
# чтобы снипет ~/.config/knrc/path.sh имел ровно одного автора — раньше
# его писал modules/python-tools.sh, а лаунчеру нужен тот же самый
# каталог в PATH ещё до того, как выбраны модули.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh и scripts/lib/rcfile.sh.
#
# Публичная точка входа: localbin::ensure_path
#
# Подключение снипета:
#   - из ~/.zshrc — строка уже зашита в config/zshrc (модуль zsh.sh
#     пишет .zshrc целиком из шаблона);
#   - из ~/.bashrc — управляемым блоком через rcfile::upsert_block.

set -euo pipefail

LOCALBIN_DIR="$HOME/.local/bin"
LOCALBIN_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"

localbin::ensure_path() {
  local snippet_dest="$LOCALBIN_STATE_DIR/path.sh"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] записал бы $snippet_dest (PATH += $LOCALBIN_DIR)"
  else
    mkdir -p "$LOCALBIN_STATE_DIR" "$LOCALBIN_DIR"
    cat > "$snippet_dest" <<EOF
# Managed by .knrc — PATH для лаунчера knrc, uv и \`uv tool install\`
# (~/.local/bin).
case ":\$PATH:" in
  *":$LOCALBIN_DIR:"*) ;;
  *) export PATH="$LOCALBIN_DIR:\$PATH" ;;
esac
EOF
  fi

  # До появления этого файла тот же снипет подключал modules/python-tools.sh
  # под маркером python-tools-path. На уже настроенных машинах старый блок
  # остался бы в ~/.bashrc и сорсил бы тот же path.sh второй раз — удаляем.
  rcfile::remove_block "$HOME/.bashrc" "python-tools-path"
  rcfile::upsert_block "$HOME/.bashrc" "localbin-path" \
    "[ -f \"$snippet_dest\" ] && source \"$snippet_dest\""

  # Подключаем в текущем процессе, чтобы всё, что ставится дальше в этом
  # же прогоне (uv -> ruff), нашлось без перелогина. Делаем и в dry-run:
  # переменная процесса — не изменение на диске.
  case ":$PATH:" in
    *":$LOCALBIN_DIR:"*) ;;
    *) export PATH="$LOCALBIN_DIR:$PATH" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/localbin.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
