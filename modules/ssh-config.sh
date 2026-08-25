#!/usr/bin/env bash
# Клиентский ~/.ssh/config: без него SSH-сессии на свежей машине молча
# отваливаются по таймауту (нет keepalive) и агент не подхватывает
# добавленные ключи.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/rcfile.sh.
#
# Публичная точка входа: ssh_config::install

set -euo pipefail

# Блок `Host *` пишется через rcfile::upsert_block, поэтому при повторном
# запуске он удаляется и заново добавляется в КОНЕЦ файла — это не
# побочный эффект, а требование: в ssh_config для большинства опций
# выигрывает первое совпадение, а у пользователя в ~/.ssh/config почти
# наверняка уже есть свои Host-блоки (например ssh-ключ/порт под
# конкретный хост) — они не должны быть перебиты нашим `Host *`, значит
# наш блок обязан идти последним.
ssh_config::_block() {
  cat <<'EOF'
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    AddKeysToAgent yes
    # HashKnownHosts no: осознанный компромисс. По умолчанию ssh хэширует
    # хосты в known_hosts, из-за чего файл нельзя ни прочитать, ни
    # вручную поправить (например удалить конкретную строку при смене
    # хоста) — только через `ssh-keygen -R`. Хэш также не даёт
    # заметных преимуществ на однопользовательской машине.
    HashKnownHosts no
EOF
}

ssh_config::install() {
  local dir="$HOME/.ssh" file="$HOME/.ssh/config"

  mkdir -p "$dir"
  chmod 700 "$dir"
  touch "$file"
  chmod 600 "$file"

  rcfile::upsert_block "$file" "ssh-config" "$(ssh_config::_block)"
  chmod 600 "$file"

  log::info "ssh-config: ~/.ssh/config обновлён (keepalive, AddKeysToAgent, HashKnownHosts no)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "modules/ssh-config.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
