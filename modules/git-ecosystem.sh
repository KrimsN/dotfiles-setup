#!/usr/bin/env bash
# Установка git-экосистемы: gh (GitHub CLI).
# git-delta ставится модулем modules/cli-tools.sh — здесь не
# дублируется, только gh.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/os-detect.sh (нужны OS_FAMILY, os::pkg_install).
#
# Публичная точка входа: git_eco::install
#
# У gh нет единого пакета в стандартных репах — GitHub публикует
# собственный apt/dnf репозиторий с инструкциями под каждую систему
# (см. https://github.com/cli/cli/blob/trunk/docs/install_linux.md).

set -euo pipefail

git_eco::install_gh_debian() {
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

  local arch
  arch="$(dpkg --print-architecture)"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  os::pkg_update
  os::pkg_install gh
}

git_eco::install_gh_rhel() {
  os::pkg_install 'dnf-command(config-manager)' \
    || log::warn "git-ecosystem: dnf-command(config-manager), возможно, уже доступен"

  case "$PKG_MANAGER" in
    dnf)
      sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      ;;
    yum)
      sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      ;;
  esac

  os::pkg_install gh
}

git_eco::install_gh() {
  if command -v gh >/dev/null 2>&1; then
    log::info "git-ecosystem: gh уже установлен, пропускаю"
    return 0
  fi

  log::info "git-ecosystem: устанавливаю gh"
  case "$OS_FAMILY" in
    debian) git_eco::install_gh_debian ;;
    rhel)   git_eco::install_gh_rhel ;;
    *)
      log::err "git-ecosystem: неизвестное семейство ОС '$OS_FAMILY', не знаю как ставить gh"
      return 1
      ;;
  esac
}

git_eco::install() {
  git_eco::install_gh
  log::info "git-ecosystem: готово. (git-delta ставится отдельно модулем modules/cli-tools.sh)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/git-ecosystem.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
