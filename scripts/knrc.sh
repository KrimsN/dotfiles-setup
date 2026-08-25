#!/usr/bin/env bash
# `knrc` — CLI проекта поверх уже установленного окружения.
#
# Запускается двумя способами, оба ведут сюда:
#   knrc <команда>            — через лаунчер ~/.local/bin/knrc, который
#                               install.sh кладёт на машину (тонкий шим,
#                               см. install_sh::_install_launcher)
#   scripts/knrc.sh <команда> — напрямую из склонированного репозитория,
#                               без установки лаунчера
#
# Команды:
#   doctor [--modules=LIST]   — диагностика окружения (ничего не меняет)
#   install [аргументы]       — прогнать install.sh (все его флаги
#                               передаются как есть)
#   help                      — справка
#
# Схема сознательно "тонкий шим + вся логика в репозитории": обновление
# CLI сводится к `git pull` в каталоге репозитория, копировать бинарник
# заново не нужно. Будущие `knrc update` и `knrc uninstall` добавляются
# сюда же — одной веткой case и одним файлом scripts/<команда>.sh, см.
# docs/modules/doctor.md.

set -euo pipefail

KNRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Модули и библиотеки проекта ожидают DOTFILES_DIR как корень репозитория.
export DOTFILES_DIR="$KNRC_DIR"

# shellcheck disable=SC1091
source "$KNRC_DIR/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$KNRC_DIR/scripts/lib/os-detect.sh"
# shellcheck disable=SC1091
source "$KNRC_DIR/scripts/lib/modules.sh"

knrc::usage() {
  cat <<EOF
knrc — управление окружением .knrc (репозиторий: $KNRC_DIR)

  knrc doctor [--modules=LIST]  диагностика: что установлено, чего нет,
                                что сломано. Ничего не чинит и не ставит.
                                Ненулевой код возврата при проблемах.
  knrc install [аргументы]      запустить install.sh (флаги --yes,
                                --dry-run и переменные окружения — как у
                                install.sh)
  knrc help                     эта справка
EOF
}

knrc::doctor() {
  # shellcheck disable=SC1091
  source "$KNRC_DIR/scripts/doctor.sh"
  # Диагностика обязана дойти до конца и напечатать все строки, даже
  # если отдельные проверки возвращают ненулевой код — а `set -e`,
  # включённый подключёнными выше библиотеками, убил бы её на первой же
  # неудачной проверке. Итог возвращается кодом doctor::run.
  set +e
  # Отчёт печатается одним потоком. log::info пишет в stdout, а
  # log::warn/log::err — в stderr (общая конвенция проекта), и при любом
  # перенаправлении (файл, пайп, лог CI) это разные потоки: строки
  # отчёта перемешиваются, и "ok"-строка одного модуля оказывается между
  # "отсутствует"-строками другого — реально ловили при тестировании.
  # Для отчёта, где порядок строк и есть содержание, это дефект, поэтому
  # склеиваем потоки на верхнем уровне, не трогая сам log.sh.
  doctor::run "$@" 2>&1
}

knrc::main() {
  local command="${1:-help}"
  if [ "$#" -gt 0 ]; then
    shift
  fi

  case "$command" in
    doctor)          knrc::doctor "$@" ;;
    install)         exec "$KNRC_DIR/install.sh" "$@" ;;
    help|--help|-h)  knrc::usage ;;
    *)
      log::err "knrc: неизвестная команда '$command'"
      knrc::usage >&2
      exit 2
      ;;
  esac
}

knrc::main "$@"
