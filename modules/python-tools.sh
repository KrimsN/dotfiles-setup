#!/usr/bin/env bash
# Установка uv (пакетный менеджер и менеджер версий Python, написан на
# Rust) и ruff (линтер/форматтер на Rust) через `uv tool install`.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh и scripts/lib/rcfile.sh.
#
# Публичная точка входа: python_tools::install
#
# uv ставится официальным скриптом astral.sh/uv/install.sh (а не через
# github_release::install, как остальные Rust-бинарники в cli-tools.sh)
# — решение пользователя: это способ доставки, который рекомендует сам
# проект uv, и он умеет самообновляться (`uv self update`).
#
# Отдельный toolchain Rust (rustup/cargo/rustc) не ставится — решение
# пользователя: uv и ruff это готовые бинарники, компилятор Rust для
# них не нужен.
#
# PATH ($HOME/.local/bin, куда uv и `uv tool install` кладут бинарники)
# управляется отдельным снипетом ~/.config/knrc/path.sh — тот же
# паттерн, что у aliases.sh/tmux.sh: подключается условной строкой из
# config/zshrc (если стоит модуль zsh) и управляемым блоком в
# ~/.bashrc через rcfile::upsert_block. Официальному uv-инсталлеру
# правка shell rc отключена явно (INSTALLER_NO_MODIFY_PATH=1), чтобы он
# не писал в файлы, которыми управляет сам проект (zsh.sh перезаписывает
# ~/.zshrc целиком из шаблона при каждом запуске — сторонние правки в
# нём не переживут повторный прогон).

set -euo pipefail

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"
PYTHON_TOOLS_BIN_DIR="$HOME/.local/bin"

python_tools::install_uv() {
  # Проверяем и PATH, и сам $PYTHON_TOOLS_BIN_DIR: при повторном запуске
  # install.sh это новый процесс, и PATH ещё не содержит
  # $PYTHON_TOOLS_BIN_DIR (её добавляет python_tools::ensure_path ниже
  # только внутри текущего запуска) — без этой проверки модуль на
  # каждом прогоне заново качал бы и переустанавливал uv.
  if command -v uv >/dev/null 2>&1 || [ -x "$PYTHON_TOOLS_BIN_DIR/uv" ]; then
    log::info "python-tools: uv уже установлен, пропускаю"
    return 0
  fi
  log::info "python-tools: устанавливаю uv через официальный скрипт astral.sh"
  curl -fsSL https://astral.sh/uv/install.sh \
    | env INSTALLER_NO_MODIFY_PATH=1 UV_INSTALL_DIR="$PYTHON_TOOLS_BIN_DIR" sh
}

python_tools::ensure_path() {
  mkdir -p "$DOTFILES_STATE_DIR"
  local snippet_dest="$DOTFILES_STATE_DIR/path.sh"

  cat > "$snippet_dest" <<EOF
# Managed by .knrc — PATH для uv и \`uv tool install\` (~/.local/bin).
case ":\$PATH:" in
  *":$PYTHON_TOOLS_BIN_DIR:"*) ;;
  *) export PATH="$PYTHON_TOOLS_BIN_DIR:\$PATH" ;;
esac
EOF

  rcfile::upsert_block "$HOME/.bashrc" "python-tools-path" \
    "[ -f \"$snippet_dest\" ] && source \"$snippet_dest\""

  # Подключаем в текущем процессе, чтобы python_tools::install_ruff ниже
  # уже видел свежепоставленный uv без перелогина.
  export PATH="$PYTHON_TOOLS_BIN_DIR:$PATH"
}

python_tools::install_ruff() {
  if command -v ruff >/dev/null 2>&1 || [ -x "$PYTHON_TOOLS_BIN_DIR/ruff" ]; then
    log::info "python-tools: ruff уже установлен, пропускаю"
    return 0
  fi
  log::info "python-tools: устанавливаю ruff через 'uv tool install'"
  uv tool install ruff
}

python_tools::install() {
  python_tools::install_uv
  python_tools::ensure_path
  python_tools::install_ruff
  log::info "python-tools: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/python-tools.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
