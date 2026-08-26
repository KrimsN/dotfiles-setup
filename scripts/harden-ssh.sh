#!/usr/bin/env bash
# Пошаговый харденинг SSH-сервера этой машины: сначала подтверждённый
# доступ по ключу, потом PermitRootLogin no и PasswordAuthentication no.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh; пользовательская точка входа — `knrc harden-ssh`
# (scripts/knrc.sh).
#
# Публичная точка входа: harden_ssh::run [--dry-run] [--force] [--rollback] [--help]
#
# Код возврата: 0 — выполнено (или нечего делать); 1 — шаг не удался;
# 2 — ошибка аргументов; 3 — нет подтверждения (ничего не изменено).
#
# Осознанно НЕ входит в KNRC_ALL_MODULES/install.sh и не участвует в
# `knrc doctor`/`knrc uninstall` (зафиксировано пользователем): это
# вмешательство в sshd рабочей машины, а не в окружение разработчика,
# необратимость (потеря доступа по SSH) серьёзнее, чем у любого другого
# модуля проекта, и у него свой план отката (--rollback), а не общий
# механизм uninstall::_plan_config.
#
# ВАЖНО: как и scripts/uninstall.sh, сознательно без `set -e` — сценарий
# обязан напечатать все предупреждения даже если один из шагов не удался.

set -uo pipefail

HARDEN_SSH_CONFIG="/etc/ssh/sshd_config"
HARDEN_SSH_FORCE=0

# --- Подтверждение ------------------------------------------------------
# Тот же принцип, что у uninstall::_confirm: ответ 'yes' целиком, а не
# [y/N] — цена случайного нажатия здесь может быть "потерян SSH-доступ к
# машине", одной буквы для этого мало.

harden_ssh::_tty_available() {
  { : < /dev/tty; } 2>/dev/null
}

harden_ssh::_confirm() {
  local prompt="$1"
  if [ "$HARDEN_SSH_FORCE" = "1" ]; then
    log::warn "harden-ssh: подтверждение получено флагом --force"
    return 0
  fi
  if ! harden_ssh::_tty_available; then
    log::err "harden-ssh: спросить подтверждение негде (нет /dev/tty) — без него не продолжаю"
    log::err "harden-ssh: явно принять риск можно только флагом --force"
    return 1
  fi
  local answer
  echo ""
  read -r -p "$(log::prompt "$prompt")" answer < /dev/tty || answer=""
  [ "$answer" = "yes" ]
}

# --- Чтение состояния -----------------------------------------------------

harden_ssh::_require_sshd() {
  if [ ! -f "$HARDEN_SSH_CONFIG" ]; then
    log::info "harden-ssh: $HARDEN_SSH_CONFIG не найден — sshd на этой машине не установлен, хардить нечего"
    return 1
  fi
  return 0
}

# Эффективное (уже резолвнутое, с учётом дефолтов и Match-блоков)
# значение директивы — надёжнее, чем grep по файлу напрямую.
harden_ssh::_effective() {
  local key="$1"
  sudo sshd -T 2>/dev/null | awk -v k="${key,,}" '$1==k{print $2; exit}'
}

harden_ssh::_already_hardened() {
  local root_login password_auth
  root_login="$(harden_ssh::_effective permitrootlogin)"
  password_auth="$(harden_ssh::_effective passwordauthentication)"
  [ "$password_auth" = "no" ] && { [ "$root_login" = "no" ] || [ "$root_login" = "prohibit-password" ]; }
}

harden_ssh::_status() {
  log::info "harden-ssh: сейчас — PermitRootLogin=$(harden_ssh::_effective permitrootlogin), PasswordAuthentication=$(harden_ssh::_effective passwordauthentication)"
}

harden_ssh::_service_name() {
  # ssh — имя сервиса на Debian/Ubuntu, sshd — на Fedora/RHEL/CentOS.
  if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
    echo ssh
  else
    echo sshd
  fi
}

# --- Шаг 1: доступ по ключу ------------------------------------------------

harden_ssh::_authorized_keys_file() {
  echo "$HOME/.ssh/authorized_keys"
}

harden_ssh::_has_key() {
  local f
  f="$(harden_ssh::_authorized_keys_file)"
  [ -s "$f" ] && grep -qE '^(ssh-|ecdsa-|sk-)' "$f"
}

harden_ssh::_step_keys() {
  local user file pubkey
  user="$(id -un)"
  file="$(harden_ssh::_authorized_keys_file)"

  echo ""
  log::info "=== шаг 1: доступ по ключу для '$user' ==="

  if harden_ssh::_has_key; then
    log::info "harden-ssh: в $file уже есть хотя бы один ключ — пропускаю добавление"
  else
    log::warn "harden-ssh: в $file ключей нет. Дальше отключается вход по паролю — без ключа доступ будет потерян."
    echo ""
    log::info "Выполните ОДНО из двух — с клиентской машины, с которой вы подключаетесь:"
    log::info "  1) ssh-copy-id -p <порт> ${user}@<адрес-этой-машины>"
    log::info "  2) вставьте публичный ключ ниже — я сам допишу его в $file"
    echo ""
    pubkey=""
    if harden_ssh::_tty_available; then
      read -r -p "$(log::prompt "Публичный ключ (ssh-ed25519/ssh-rsa ...) или пусто, если сделали через ssh-copy-id: ")" pubkey < /dev/tty || pubkey=""
    else
      log::warn "harden-ssh: спросить ключ негде (нет /dev/tty) — добавьте его через ssh-copy-id и запустите команду снова"
    fi

    if [ -n "$pubkey" ]; then
      if ! grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-)' <<<"$pubkey"; then
        log::err "harden-ssh: строка не похожа на публичный SSH-ключ (нет ssh-ed25519/ssh-rsa/... в начале) — не добавляю"
        return 1
      fi
      if [ "${DRY_RUN:-0}" = "1" ]; then
        log::info "[dry-run] дописал бы ключ в $file"
      else
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        touch "$file"
        chmod 600 "$file"
        if grep -qxF "$pubkey" "$file" 2>/dev/null; then
          log::info "harden-ssh: этот ключ уже есть в $file"
        else
          printf '%s\n' "$pubkey" >> "$file"
          log::info "harden-ssh: ключ добавлен в $file"
        fi
      fi
    fi
  fi

  [ "${DRY_RUN:-0}" = "1" ] && return 0

  if ! harden_ssh::_has_key; then
    log::err "harden-ssh: ключа в $file всё ещё нет — отключать вход по паролю нельзя, прерываю"
    return 1
  fi

  echo ""
  log::warn "ОБЯЗАТЕЛЬНО перед продолжением: откройте НОВОЕ окно/вкладку терминала и"
  log::warn "убедитесь, что 'ssh ${user}@<адрес-этой-машины>' пускает по ключу БЕЗ пароля."
  log::warn "Текущую сессию не закрывайте — она останется рабочей, даже если новая не получится."
  harden_ssh::_confirm "Вход по ключу в новой сессии проверен и работает? Введите 'yes': " || {
    log::info "harden-ssh: отменено — вход по паролю остаётся включён"
    return 1
  }
}

# --- Шаг 2: применение директив --------------------------------------------

# Первое совпадение (закомментированное или нет) заменяется целиком;
# если директивы в файле ещё нет — дописывается в конец. sshd, как и
# ssh_config, берёт первое встретившееся значение по каждому ключу — то
# же правило учтено в modules/ssh-config.sh.
harden_ssh::_apply_directive() {
  local key="$1" value="$2"
  if sudo grep -qE "^[[:space:]]*#?[[:space:]]*${key}\\b" "$HARDEN_SSH_CONFIG"; then
    sudo sed -i "0,/^[[:space:]]*#\\?[[:space:]]*${key}\\b.*/s//${key} ${value}/" "$HARDEN_SSH_CONFIG"
  else
    printf '%s %s\n' "$key" "$value" | sudo tee -a "$HARDEN_SSH_CONFIG" >/dev/null
  fi
}

harden_ssh::_backup() {
  local backup
  backup="${HARDEN_SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  sudo cp "$HARDEN_SSH_CONFIG" "$backup"
  echo "$backup"
}

harden_ssh::_reload() {
  local svc
  svc="$(harden_ssh::_service_name)"
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl reload "$svc" 2>/dev/null && return 0
    sudo systemctl restart "$svc" 2>/dev/null && return 0
  fi
  # Без systemd (WSL, некоторые контейнеры) — тот же init-скрипт, что
  # использует modules/docker.sh и test-контур проекта.
  sudo service "$svc" restart 2>/dev/null
}

harden_ssh::_step_apply() {
  echo ""
  log::info "=== шаг 2: PermitRootLogin no, PasswordAuthentication no ==="

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] бэкап $HARDEN_SSH_CONFIG, PermitRootLogin no, PasswordAuthentication no, 'sshd -t', перезагрузка $(harden_ssh::_service_name)"
    return 0
  fi

  local backup
  backup="$(harden_ssh::_backup)"
  log::info "harden-ssh: бэкап сохранён в $backup"

  harden_ssh::_apply_directive PermitRootLogin no
  harden_ssh::_apply_directive PasswordAuthentication no

  if ! sudo sshd -t; then
    log::err "harden-ssh: 'sshd -t' нашёл ошибку в конфиге — откатываю $backup, sshd не перезагружаю"
    sudo cp "$backup" "$HARDEN_SSH_CONFIG"
    return 1
  fi

  if ! harden_ssh::_reload; then
    log::err "harden-ssh: не удалось перезагрузить sshd — конфиг изменён, но не применён. Откат: 'knrc harden-ssh --rollback'"
    return 1
  fi

  log::info "harden-ssh: sshd перезагружен. PermitRootLogin=no, PasswordAuthentication=no."
  log::warn "НЕ закрывайте эту сессию. Откройте НОВОЕ окно и проверьте вход — при проблеме: 'knrc harden-ssh --rollback'."
}

# --- Откат ------------------------------------------------------------

harden_ssh::_latest_backup() {
  sudo find "$(dirname "$HARDEN_SSH_CONFIG")" -maxdepth 1 \
    -name "$(basename "$HARDEN_SSH_CONFIG").bak.*" 2>/dev/null | sort | tail -n1
}

harden_ssh::_rollback() {
  local latest
  latest="$(harden_ssh::_latest_backup)"
  if [ -z "$latest" ]; then
    log::err "harden-ssh: бэкапов ${HARDEN_SSH_CONFIG}.bak.* не найдено — откатывать нечего"
    return 1
  fi

  log::info "harden-ssh: план отката — вернуть $latest в $HARDEN_SSH_CONFIG и перезагрузить sshd"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] изменений не будет"
    return 0
  fi

  harden_ssh::_confirm "Продолжить откат? Введите 'yes': " || {
    log::info "harden-ssh: отменено"
    return 3
  }

  sudo cp "$latest" "$HARDEN_SSH_CONFIG"
  if ! sudo sshd -t; then
    log::err "harden-ssh: восстановленный бэкап не проходит 'sshd -t' — sshd не перезагружаю, разбирайтесь вручную"
    return 1
  fi
  harden_ssh::_reload
  log::info "harden-ssh: откат выполнен, sshd перезагружен."
}

# --- Точка входа --------------------------------------------------------

harden_ssh::_usage() {
  cat <<EOF
knrc harden-ssh — пошаговый харденинг SSH-сервера этой машины: сначала
подтверждённый доступ по ключу, затем PermitRootLogin no и
PasswordAuthentication no. Опциональная команда — вне install.sh и
'knrc doctor'/'knrc uninstall', запускается только явно.

  --dry-run    показать план, ничего не менять
  --force      не спрашивать подтверждений (риск потери SSH-доступа —
                убедитесь в ключе заранее)
  --rollback   вернуть последний бэкап $HARDEN_SSH_CONFIG и перезагрузить sshd
  --help       эта справка

Код возврата: 0 — выполнено/нечего делать, 1 — шаг не удался,
2 — ошибка аргументов, 3 — нет подтверждения (ничего не изменено).
EOF
}

harden_ssh::run() {
  local dry_run="${DRY_RUN:-0}" rollback=0 arg
  HARDEN_SSH_FORCE=0

  for arg in "$@"; do
    case "$arg" in
      --dry-run)  dry_run=1 ;;
      --force)    HARDEN_SSH_FORCE=1 ;;
      --rollback) rollback=1 ;;
      --help|-h)  harden_ssh::_usage; return 0 ;;
      *)
        log::err "harden-ssh: неизвестный аргумент '$arg'"
        harden_ssh::_usage >&2
        return 2
        ;;
    esac
  done
  export DRY_RUN="$dry_run"

  harden_ssh::_require_sshd || return 0

  if [ "$rollback" = "1" ]; then
    harden_ssh::_rollback
    return $?
  fi

  # Единственный аккаунт на машине — root: после хардена root по SSH
  # больше не войдёт, а другого пользователя с ключом и sudo может не
  # быть — тогда доступ теряется безвозвратно. В отличие от остальных
  # подтверждений это не про "ключ проверен", а про сам факт запуска от
  # root, поэтому проверяется раньше и отдельно.
  if [ "$(id -u)" = "0" ] && [ "$dry_run" != "1" ]; then
    log::warn "harden-ssh: вы root. После хардена вход root по SSH отключается — если нет отдельного"
    log::warn "пользователя с sudo и ключом, доступ будет потерян безвозвратно."
    harden_ssh::_confirm "Всё равно продолжить от root? Введите 'yes': " || return 3
  fi

  harden_ssh::_status

  if harden_ssh::_already_hardened; then
    log::info "harden-ssh: уже захардено (PermitRootLogin=no/prohibit-password, PasswordAuthentication=no) — делать нечего"
    return 0
  fi

  harden_ssh::_step_keys || return $?
  harden_ssh::_step_apply || return $?
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/harden-ssh.sh: подключать через source, не запускать напрямую (используй 'knrc harden-ssh')" >&2
  exit 1
fi
