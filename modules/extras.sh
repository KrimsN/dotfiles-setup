#!/usr/bin/env bash
# Установка "прочего" из списка программ: tldr, fastfetch.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh, scripts/lib/epel.sh и
# scripts/lib/github-release.sh (нужны OS_FAMILY, os::pkg_install,
# epel::ensure, github_release::install).
#
# Публичная точка входа: extras::install
#
# neofetch (изначальный выбор) archived апстримом и убран из
# репозиториев Fedora — заменён на fastfetch (активно поддерживаемый
# форк, похожий вывод/конфиг), решение пользователя.
#
# fastfetch при этом отсутствует и в стандартных репах Debian/Ubuntu
# (только Fedora/EPEL его содержат), поэтому ставится единообразно
# musl-бинарником с GitHub Releases — тем же паттерном, что eza/delta/
# curlie/zoxide в modules/cli-tools.sh.
#
# tldr есть в базовых репах везде (на CentOS/RHEL — через EPEL),
# ставится через пакетный менеджер.

set -euo pipefail

extras::install_tldr() {
  epel::ensure
  log::info "extras: устанавливаю tldr"
  os::pkg_install tldr
}

extras::install_fastfetch() {
  # У fastfetch ассет "musl" вопреки названию не статический, а
  # динамически слинкован с musl libc — на glibc-дистрибутивах (все
  # наши целевые) не запускается ("required file not found", нет
  # ld-musl рантайма). Берём обычную glibc-сборку "linux-<arch>".
  local asset_regex
  case "$(uname -m)" in
    x86_64) asset_regex='fastfetch-linux-amd64\.tar\.gz$' ;;
    aarch64|arm64) asset_regex='fastfetch-linux-aarch64\.tar\.gz$' ;;
    *) asset_regex='fastfetch-linux-amd64\.tar\.gz$' ;;
  esac
  github_release::install "fastfetch-cli/fastfetch" "$asset_regex" "usr/bin/fastfetch" "fastfetch"
}

extras::install() {
  extras::install_tldr
  extras::install_fastfetch
  log::info "extras: готово."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/extras.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
