#!/usr/bin/env bash
# Настройка ~/.gitconfig: pager (delta), редактор, разумные дефолты
# самого git и глобальный gitignore.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh.
#
# Публичная точка входа: git_config::install
#
# Настраиваем через `git config --global <key> <value>`, а НЕ
# копированием готового ~/.gitconfig: копирование затёрло бы
# собственные настройки пользователя (и его user.name/user.email),
# а `git config` идемпотентен по природе — повторный прогон просто
# перезапишет те же ключи теми же значениями.
#
# delta и nvim ставятся другими модулями (cli-tools.sh и nvim.sh), и
# оба могут быть не выбраны при установке. Поэтому все ключи, которые
# ссылаются на конкретный бинарник, выставляются только под guard'ом
# `command -v` — тот же приём, что в config/aliases.sh для bat/eza:
# конфиг, ссылающийся на несуществующий pager, ломает вообще любой
# `git diff`, а не только красивый вывод.

set -euo pipefail

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"

# Ключи ~/.gitconfig, которыми управляет модуль, объявлены таблицами, а
# не строчками внутри функций, потому что у них появился второй
# потребитель: `knrc uninstall` снимает ровно те ключи, которые
# выставила установка, и только если значение совпадает с нашим
# (scripts/uninstall.sh подключает этот файл ради этих массивов).
# Разъезд двух списков означал бы, что часть настроек остаётся в
# ~/.gitconfig после удаления — поэтому список один.
#
# Формат элемента — "<ключ>=<значение>"; значение может содержать
# пробелы ("delta --color-only"), поэтому режется по ПЕРВОМУ '='.
# shellcheck disable=SC2034 # читается и scripts/uninstall.sh
GIT_CONFIG_DEFAULTS=(
  "init.defaultBranch=master"
  "pull.rebase=true"
  "push.autoSetupRemote=true"
  "rerere.enabled=true"
  "diff.algorithm=histogram"
)

# zdiff3 показывает в конфликте общего предка — с delta это заметно
# полезнее дефолтного merge-стиля, поэтому ключ живёт здесь, а не в
# общих дефолтах: без delta он не выставляется.
# shellcheck disable=SC2034 # читается и scripts/uninstall.sh
GIT_CONFIG_PAGER=(
  "core.pager=delta"
  "interactive.diffFilter=delta --color-only"
  "delta.navigate=true"
  "delta.line-numbers=true"
  "merge.conflictStyle=zdiff3"
)

# shellcheck disable=SC2034 # читается и scripts/uninstall.sh
GIT_CONFIG_EDITOR=(
  "core.editor=nvim"
)

git_config::_dotfiles_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
}

git_config::_set() {
  git config --global "$1" "$2"
}

# Выставить пачку ключей из таблицы вида "<ключ>=<значение>".
git_config::_set_all() {
  local pair
  for pair in "$@"; do
    git_config::_set "${pair%%=*}" "${pair#*=}"
  done
}

# Значение уже выставлено в ~/.gitconfig (или в любом другом файле,
# который git считает глобальным)?
git_config::_has() {
  git config --global --get "$1" >/dev/null 2>&1
}

git_config::setup_pager() {
  if ! command -v delta >/dev/null 2>&1; then
    log::warn "git-config: delta не найден в PATH, pager не настраиваю (модуль cli-tools не устанавливался?)"
    return 0
  fi

  log::info "git-config: настраиваю delta как pager"
  git_config::_set_all "${GIT_CONFIG_PAGER[@]}"
}

git_config::setup_editor() {
  if ! command -v nvim >/dev/null 2>&1; then
    log::warn "git-config: nvim не найден в PATH, core.editor не трогаю (модуль nvim не устанавливался?)"
    return 0
  fi

  log::info "git-config: core.editor = nvim"
  git_config::_set_all "${GIT_CONFIG_EDITOR[@]}"
}

git_config::setup_defaults() {
  log::info "git-config: выставляю общие дефолты git"
  git_config::_set_all "${GIT_CONFIG_DEFAULTS[@]}"
}

# Путь к глобальному gitignore в том виде, в каком он попадает в
# ~/.gitconfig: через `~`, а не абсолютный — git сам раскрывает `~/` в
# значении core.excludesFile, а такой конфиг переносим между машинами с
# разными $HOME. Вынесено в функцию, потому что то же значение нужно
# `knrc uninstall`: снимать core.excludesFile можно только если он всё
# ещё указывает на наш файл, а не на пользовательский.
git_config::excludes_value() {
  local dest="$DOTFILES_STATE_DIR/gitignore_global"
  # shellcheck disable=SC2088 # тильда ниже и должна остаться нераскрытой: раскрывает её сам git
  case "$dest" in
    "$HOME"/*) echo "~/${dest#"$HOME"/}" ;;
    *)         echo "$dest" ;;
  esac
}

git_config::setup_excludes() {
  local snippet_src snippet_dest
  snippet_src="$(git_config::_dotfiles_dir)/config/gitignore_global"
  snippet_dest="$DOTFILES_STATE_DIR/gitignore_global"

  mkdir -p "$DOTFILES_STATE_DIR"
  cp "$snippet_src" "$snippet_dest"

  git_config::_set core.excludesFile "$(git_config::excludes_value)"
  log::info "git-config: глобальный gitignore установлен ($snippet_dest)"
}

# user.name / user.email — единственное, что нельзя выставить за
# пользователя. Спрашиваем через /dev/tty (а не stdin: при
# `curl ... | bash` stdin занят телом скрипта — см. CLAUDE.md, раздел
# "Механизм конфигурации"). Уже заполненные значения не трогаем и не
# переспрашиваем — это делает повторный прогон полностью молчаливым.
# `[ -r /dev/tty ]` здесь недостаточно: в контейнере без выделенного
# терминала (docker run без -t, CI) файл /dev/tty существует и проходит
# проверку -r, но открытие падает с "No such device or address" — что и
# ловили при тестировании модуля. Единственная надёжная проверка —
# попробовать открыть устройство.
git_config::_tty_available() {
  { : < /dev/tty; } 2>/dev/null
}

git_config::_ask_identity_field() {
  local key="$1" question="$2" answer=""

  if git_config::_has "$key"; then
    log::info "git-config: $key уже выставлен ($(git config --global --get "$key")), не трогаю"
    return 0
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || ! git_config::_tty_available; then
    return 0
  fi

  read -r -p "$(log::prompt "$question (пусто — пропустить): ")" answer < /dev/tty || answer=""
  if [ -n "$answer" ]; then
    git_config::_set "$key" "$answer"
  fi
}

git_config::setup_identity() {
  git_config::_ask_identity_field user.name "git user.name"
  git_config::_ask_identity_field user.email "git user.email"
}

git_config::install() {
  if ! command -v git >/dev/null 2>&1; then
    log::err "git-config: git не найден в PATH — сначала поставь модуль base"
    return 1
  fi

  git_config::setup_defaults
  git_config::setup_pager
  git_config::setup_editor
  git_config::setup_excludes
  git_config::setup_identity
  log::info "git-config: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/git-config.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
