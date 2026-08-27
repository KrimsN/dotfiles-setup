#!/usr/bin/env bash
# Обновление уже установленного .knrc: git-клон в $DOTFILES_DIR
# подтягивается до последней версии, затем перезапускается install.sh
# — тот самый путь, которым доустанавливаются новые модули и который
# делает `update` идемпотентным, а не отдельной процедурой
# самообновления CLI (см. docs/modules/doctor.md, раздел про схему
# "тонкий шим").
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh; пользовательская точка входа — `knrc update`
# (scripts/knrc.sh).
#
# Публичная точка входа: update::run [--dry-run] [--help] [аргументы
#                                     install.sh]
# Аргументы, которые update.sh сам не распознаёт, передаются дальше в
# install.sh (--yes, DOTFILES_MODULES и т.п.) — так `knrc update --yes`
# работает так же предсказуемо, как `knrc install --yes`.
#
# Код возврата: 0 — обновлено (или уже была последняя версия);
# 1 — git pull не удался (грязное дерево, конфликт, нет сети);
# 2 — ошибка аргументов.
#
# ВАЖНО: файл сознательно НЕ включает `set -e` — та же причина, что у
# scripts/doctor.sh и scripts/uninstall.sh: knrc.sh снимает `set -e`
# перед вызовом update::run и сам решает, что делать с кодом возврата.

set -uo pipefail

update::_usage() {
  cat <<'EOF'
knrc update [--dry-run] [аргументы install.sh]

  Обновляет локальный клон .knrc (git pull --ff-only) и перезапускает
  install.sh, чтобы подтянуть новые модули так же, как при первой
  установке. Все нераспознанные аргументы передаются install.sh как
  есть (--yes, DOTFILES_MODULES=... и т.п.).

  --dry-run   показать, что будет обновлено (git fetch + список
              входящих коммитов), не трогая рабочую копию.
  --help      эта справка.
EOF
}

# Есть ли в рабочей копии незакоммиченные изменения. Обновлять поверх
# них через --ff-only всё равно бессмысленно (fast-forward требует
# чистого дерева), но явная проверка даёт понятное сообщение вместо
# сырой ошибки git.
update::_dirty() {
  [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]
}

update::run() {
  local dry_run=0
  local -a passthrough=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --help|-h) update::_usage; return 0 ;;
      *) passthrough+=("$1") ;;
    esac
    shift
  done

  if [ ! -d "$DOTFILES_DIR/.git" ]; then
    log::err "update: $DOTFILES_DIR не git-клон — переустановите .knrc заново"
    return 1
  fi

  if update::_dirty; then
    log::err "update: в $DOTFILES_DIR есть незакоммиченные изменения — обновление остановлено"
    log::err "update: закоммитьте/спрячьте их (git -C \"$DOTFILES_DIR\" stash) или переустановите .knrc"
    return 1
  fi

  local branch
  branch="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

  if [ "$dry_run" = "1" ]; then
    log::info "[dry-run] update: git fetch в $DOTFILES_DIR"
    if ! git -C "$DOTFILES_DIR" fetch --quiet; then
      log::err "update: git fetch не удался (нет сети?)"
      return 1
    fi
    local incoming
    incoming="$(git -C "$DOTFILES_DIR" log --oneline "HEAD..@{upstream}" 2>/dev/null || true)"
    if [ -z "$incoming" ]; then
      log::info "[dry-run] update: уже последняя версия ($branch)"
    else
      log::info "[dry-run] update: подтянулись бы коммиты:"
      echo "$incoming" >&2
    fi
    log::info "[dry-run] update: затем перезапустил бы install.sh ${passthrough[*]:-}"
    return 0
  fi

  log::info "update: git pull --ff-only в $DOTFILES_DIR ($branch)"
  if ! git -C "$DOTFILES_DIR" pull --ff-only; then
    log::err "update: git pull --ff-only не удался — история разошлась или нет сети"
    log::err "update: разберитесь вручную в $DOTFILES_DIR (git status/git log) и повторите"
    return 1
  fi

  log::info "update: перезапускаю install.sh, чтобы подтянуть новые модули"
  DOTFILES_DIR="$DOTFILES_DIR" exec "$DOTFILES_DIR/install.sh" "${passthrough[@]}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/update.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
