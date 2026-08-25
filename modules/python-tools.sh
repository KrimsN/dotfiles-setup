#!/usr/bin/env bash
# Установка uv (пакетный менеджер и менеджер версий Python, написан на
# Rust) и ruff (линтер/форматтер на Rust) через `uv tool install`.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh, scripts/lib/localbin.sh, scripts/lib/pkg-registry.sh
# (нужны localbin::ensure_path и pkg::install).
#
# Публичная точка входа: python_tools::install
#
# Способ установки uv (официальный установщик astral.sh/uv/install.sh, а
# не github_release::install, как остальные Rust-бинарники в
# cli-tools.sh — решение пользователя: это способ доставки, который
# рекомендует сам проект uv, и он умеет самообновляться через
# `uv self update`) и ruff (`uv tool install ruff`, см.
# python_tools::install_ruff ниже — на неё ссылается data/packages/
# registry.json как на custom-обработчик) описаны декларативно в
# data/packages/registry.json, см. docs/design/pkg-metadata-json.md.
#
# Отдельный toolchain Rust (rustup/cargo/rustc) не ставится — решение
# пользователя: uv и ruff это готовые бинарники, компилятор для них не
# нужен.
#
# PATH ($HOME/.local/bin, куда uv и `uv tool install` кладут бинарники)
# управляется отдельным снипетом ~/.config/knrc/path.sh — тот же
# паттерн, что у aliases.sh/tmux.sh: подключается условной строкой из
# config/zshrc (если стоит модуль zsh) и управляемым блоком в
# ~/.bashrc. Сам снипет пишет не этот
# модуль, а scripts/lib/localbin.sh: в тот же каталог install.sh
# ставит лаунчер `knrc`, и PATH нужен даже когда модуль python-tools
# не выбран. Официальному uv-инсталлеру
# правка shell rc отключена явно (INSTALLER_NO_MODIFY_PATH=1, см.
# data/packages/methods/curl-sh.json), чтобы он не писал в файлы,
# которыми управляет сам проект (zsh.sh перезаписывает ~/.zshrc целиком
# из шаблона при каждом запуске — сторонние правки в нём не переживут
# повторный прогон).
#
# localbin::ensure_path вызывается МЕЖДУ установкой uv и ruff (не
# после обоих) — `uv tool install ruff` внутри python_tools::install_ruff
# должен найти `uv` в PATH уже в текущем процессе, без перелогина.

set -euo pipefail

PYTHON_TOOLS_BIN_DIR="$HOME/.local/bin"

# custom-обработчик для пакета 'ruff' в data/packages/registry.json
# (метод type=custom, handler="python_tools::install_ruff") — диспетчер
# pkg::install вызывает эту функцию по имени, см.
# scripts/lib/pkg-registry.sh:pkg_registry::_run_custom. Идемпотентность
# и DRY_RUN для custom-методов не централизованы в диспетчере (см.
# docs/design/pkg-metadata-json.md) — эта функция отвечает за них сама.
python_tools::install_ruff() {
  if command -v ruff >/dev/null 2>&1 || [ -x "$PYTHON_TOOLS_BIN_DIR/ruff" ]; then
    log::info "python-tools: ruff уже установлен, пропускаю"
    return 0
  fi
  log::info "python-tools: устанавливаю ruff через 'uv tool install'"
  uv tool install ruff
}

python_tools::install() {
  pkg::install uv
  localbin::ensure_path
  pkg::install ruff
  log::info "python-tools: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/python-tools.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
