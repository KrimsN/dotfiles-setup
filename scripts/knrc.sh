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
#   update [--dry-run]        — обновить клон (git pull --ff-only) и
#                               перезапустить install.sh
#   uninstall [аргументы]     — откат установки (спрашивает подтверждение)
#   harden-ssh [аргументы]    — опционально: харденинг SSH этой машины
#                               (спрашивает подтверждение, свой --rollback)
#   help                      — справка
#
# Схема сознательно "тонкий шим + вся логика в репозитории": обновление
# CLI сводится к `git pull` в каталоге репозитория, копировать бинарник
# заново не нужно — см. scripts/update.sh и docs/modules/update.md.

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
# rcfile::remove_block и state::read нужны команде uninstall; подключаем
# здесь, рядом с остальными библиотеками, а не внутри ветки case —
# сорсить библиотеки из-под команды значит иметь два разных набора
# доступных функций в зависимости от аргумента.
# shellcheck disable=SC1091
source "$KNRC_DIR/scripts/lib/rcfile.sh"
# shellcheck disable=SC1091
source "$KNRC_DIR/scripts/lib/state.sh"

knrc::usage() {
  cat <<EOF
knrc — управление окружением .knrc (репозиторий: $KNRC_DIR)

  knrc doctor [--modules=LIST]  диагностика: что установлено, чего нет,
                                что сломано. Ничего не чинит и не ставит.
                                Ненулевой код возврата при проблемах.
  knrc install [аргументы]      запустить install.sh (флаги --yes,
                                --dry-run и переменные окружения — как у
                                install.sh)
  knrc update [--dry-run]       обновить локальный клон (git pull
                                --ff-only) и перезапустить install.sh,
                                чтобы подтянуть новые модули. '--dry-run'
                                показывает входящие коммиты без слияния.
                                Отказывает при незакоммиченных правках
                                в клоне. Аргументы, кроме '--dry-run',
                                передаются install.sh как есть.
  knrc uninstall [аргументы]    откат установки: вернуть конфиги из
                                бэкапов, убрать установленное нами,
                                вернуть login-shell. Спрашивает
                                подтверждение; '--dry-run' показывает
                                план, '--help' — все флаги.
  knrc harden-ssh [аргументы]   опционально, только по запросу: отключить
                                root-логин и вход по паролю по SSH после
                                подтверждённого доступа по ключу. Своя
                                команда '--rollback', не часть uninstall.
                                '--help' — все флаги.
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

knrc::uninstall() {
  # shellcheck disable=SC1091
  source "$KNRC_DIR/scripts/uninstall.sh"
  # Ровно та же пара приёмов, что и у doctor выше, по тем же причинам:
  # `set -e` убил бы откат на первом же шаге, который не удался (а
  # оставшиеся шаги выполнить надо), а разделённые stdout/stderr
  # перемешали бы строки плана при перенаправлении в файл.
  set +e
  uninstall::run "$@" 2>&1
}

knrc::update() {
  # shellcheck disable=SC1091
  source "$KNRC_DIR/scripts/update.sh"
  # Без склейки потоков (в отличие от doctor/uninstall выше): успешный
  # update заканчивается `exec install.sh`, и это должно вести себя
  # так же, как прямой `knrc install` — со своими раздельными
  # stdout/stderr, а не смешанными в один поток.
  set +e
  update::run "$@"
}

knrc::harden_ssh() {
  # shellcheck disable=SC1091
  source "$KNRC_DIR/scripts/harden-ssh.sh"
  # Та же пара приёмов, что у doctor/uninstall выше: `set -e` убил бы
  # сценарий на первом неудачном шаге, а нужно дойти до финальных
  # предупреждений; склейка потоков — чтобы порядок строк плана не
  # разъезжался при перенаправлении.
  set +e
  harden_ssh::run "$@" 2>&1
}

knrc::main() {
  local command="${1:-help}"
  if [ "$#" -gt 0 ]; then
    shift
  fi

  case "$command" in
    doctor)          knrc::doctor "$@" ;;
    uninstall)       knrc::uninstall "$@" ;;
    harden-ssh)      knrc::harden_ssh "$@" ;;
    install)         exec "$KNRC_DIR/install.sh" "$@" ;;
    update)          knrc::update "$@" ;;
    help|--help|-h)  knrc::usage ;;
    *)
      log::err "knrc: неизвестная команда '$command'"
      knrc::usage >&2
      exit 2
      ;;
  esac
}

knrc::main "$@"
