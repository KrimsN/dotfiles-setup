#!/usr/bin/env bash
# Откат установки: вернуть машину к тому, что было до install.sh.
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh, scripts/lib/os-detect.sh, scripts/lib/rcfile.sh,
# scripts/lib/state.sh и scripts/lib/modules.sh; пользовательская точка
# входа — `knrc uninstall` (scripts/knrc.sh).
#
# Публичная точка входа: uninstall::run [--dry-run] [--force]
#                                       [--modules=LIST] [--help]
#
# Код возврата: 0 — всё выполнено; 1 — часть шагов не удалась;
# 2 — ошибка аргументов; 3 — нет подтверждения (ничего не делалось).
#
# ВАЖНО: файл сознательно НЕ включает `set -e` (та же причина, что у
# scripts/doctor.sh). Удаление обязано дойти до конца: если один шаг
# упал (файл занят, нет прав), остальные всё равно надо выполнить, а
# про упавший — сказать. Итог возвращается кодом uninstall::run.
#
# ВАЖНО-2: при `pipefail` нельзя писать `команда | grep -q ОБРАЗЕЦ` в
# условии — см. подробный разбор в шапке scripts/doctor.sh. Здесь grep
# везде читает из here-string.
#
# --- Как устроено -----------------------------------------------------
#
# Две фазы, разделённые подтверждением:
#
#   1. ПЛАН. Ничего не меняется, только читается система. Каждое
#      действие кладётся в UNINSTALL_ACTIONS и печатается. Сюда же
#      собирается список "останется в системе" (UNINSTALL_LEFTOVERS).
#   2. ВЫПОЛНЕНИЕ. Проигрывается тот же массив.
#
# Из этого следует главное свойство: `--dry-run` — это буквально первая
# фаза без второй, а не отдельная ветка кода с собственными `if`. План,
# который пользователь видит перед вопросом "точно удалять?", и есть
# то, что будет выполнено.
#
# --- Как решается, "наш" ли файл --------------------------------------
#
# Установка меняет пользовательские файлы тремя разными способами, и
# откат у каждого свой:
#
#   1. Копирование поверх с бэкапом (~/.zshrc, ~/.tmux.conf,
#      ~/.config/nvim/init.lua, ~/.config/bat/config). Модули делают
#      бэкап по единой схеме `<путь>.bak.<YYYYMMDDHHMMSS>` — она
#      совпадает во всех четырёх модулях, поэтому отдельного разбора
#      "у кого какая схема" здесь нет (см. docs/modules/uninstall.md).
#      Откат: вернуть самый свежий бэкап, а если его нет (файла до нас
#      не было) — удалить файл.
#   2. Маркированный блок в чужом файле (~/.bashrc, ~/.ssh/config).
#      Бэкапа нет и не нужно — откат это rcfile::remove_block.
#   3. Ключи `git config --global`. Бэкапа тоже нет: модуль намеренно
#      не копирует ~/.gitconfig целиком. Откат — снять ровно те ключи,
#      которые ставили, и только если значение всё ещё наше.
#
# Общее правило для (1): трогаем файл, только если он всё ещё НАШ —
# побайтово совпадает с версией из репозитория ИЛИ содержит маркер
# ".knrc". Файл, который пользователь правил руками, не удаляется и не
# перезаписывается бэкапом, а попадает в "осталось". Это же правило
# делает повторный запуск uninstall безопасным: восстановленный
# пользовательский конфиг вторым прогоном уже не опознаётся как наш.
#
# --- Чего uninstall НЕ делает ------------------------------------------
#
#   - Не удаляет пакеты пакетного менеджера. Они могли стоять до нас
#     или быть нужны системе (git, curl, vim, unzip). Вместо этого —
#     список в конце и готовая команда удаления.
#   - Не трогает `*.local`-файлы (~/.zshrc.local, ~/.tmux.conf.local,
#     ~/.config/knrc/aliases.local.sh) — это точки расширения, их
#     содержимое принадлежит пользователю, а не проекту.
#   - Не удаляет сам каталог репозитория: из него прямо сейчас
#     выполняется этот код, и он мог быть склонирован пользователем
#     вручную в рабочий каталог. Путь и команда — в "осталось".

set -uo pipefail

UNINSTALL_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
UNINSTALL_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"
UNINSTALL_LOCALBIN="$HOME/.local/bin"
UNINSTALL_RUN_LOG="$HOME/.knrc.log"
UNINSTALL_REGISTRY_DIR="$UNINSTALL_DIR/data/packages"

# Списки пакетов берутся из самих модулей, а не переписываются здесь:
# разъехавшиеся списки означали бы, что часть установленного не попадёт
# ни в удаление, ни даже в отчёт "осталось". Ради этого модули и держат
# свои наборы в константах верхнего уровня (CLI_PACKAGES,
# DIAGNOSTICS_PACKAGES, EXTRAS_PACKAGES), а git-config — таблицы ключей.
# Подключение самих файлов безопасно: на верхнем уровне у них только
# объявления, ничего не выполняется.
# shellcheck disable=SC1091
source "$UNINSTALL_DIR/modules/cli-tools.sh"
# shellcheck disable=SC1091
source "$UNINSTALL_DIR/modules/diagnostics.sh"
# shellcheck disable=SC1091
source "$UNINSTALL_DIR/modules/extras.sh"
# shellcheck disable=SC1091
source "$UNINSTALL_DIR/modules/git-config.sh"
# shellcheck disable=SC1091
source "$UNINSTALL_DIR/modules/zsh-terminal-app.sh"
# Подключённые модули включают `set -e` у себя — возвращаем режим,
# который нужен именно здесь (см. "ВАЖНО" в шапке).
set +e

UNINSTALL_ACTIONS=()
UNINSTALL_LEFTOVERS=()
UNINSTALL_ERRORS=0
UNINSTALL_HAVE_JQ=0
UNINSTALL_FORCE=0

# --- Примитивы плана --------------------------------------------------

uninstall::_section() {
  echo ""
  log::info "=== $1 ==="
}

# uninstall::_add <тип> [аргументы...] — добавить действие в план и
# сразу его показать. Поля записи разделены табом (в путях его не
# бывает, а в пробелах — сколько угодно).
uninstall::_add() {
  local record="$1" arg
  shift
  for arg in "$@"; do
    record+=$'\t'"$arg"
  done
  UNINSTALL_ACTIONS+=("$record")
  log::info "  $(uninstall::_describe "$record")"
}

# Человекочитаемое описание действия. Одно на план и на выполнение —
# чтобы строка "что собираемся сделать" и строка "что сделали" не могли
# разойтись по смыслу.
uninstall::_describe() {
  local -a f=()
  IFS=$'\t' read -r -a f <<<"$1"
  case "${f[0]}" in
    restore)      echo "восстановить ${f[1]} из бэкапа ${f[2]}" ;;
    rm)           echo "удалить файл ${f[1]}" ;;
    sudo_rm)      echo "удалить файл ${f[1]} (sudo)" ;;
    rmtree)       echo "удалить каталог ${f[1]}" ;;
    sudo_rmtree)  echo "удалить каталог ${f[1]} (sudo)" ;;
    rmdir_empty)  echo "удалить каталог ${f[1]}, если он опустеет" ;;
    rm_if_empty)  echo "удалить ${f[1]}, если он останется пустым" ;;
    rcblock)      echo "убрать блок knrc:${f[2]} из ${f[1]}" ;;
    gitunset)     echo "снять git-настройку ${f[1]}" ;;
    chsh)         echo "вернуть login-shell пользователя на ${f[1]}" ;;
    dockergroup)  echo "вывести ${f[1]} из группы docker" ;;
    uvtool)       echo "удалить ${f[1]} через 'uv tool uninstall'" ;;
    pipuninstall) echo "удалить ${f[1]} через 'pip3 uninstall'" ;;
    fccache)      echo "обновить кэш шрифтов (fc-cache)" ;;
    state_forget) echo "забыть запись о состоянии '${f[1]}'" ;;
    gsettings_unbind) echo "снять хоткей GNOME (${f[1]})" ;;
    *)            echo "неизвестное действие: $1" ;;
  esac
}

# То, что останется в системе после удаления, с подсказкой как убрать
# руками. Печатается одним блоком в самом конце — это ответ на
# требование "явно сообщить списком, что осталось".
uninstall::_leftover() {
  UNINSTALL_LEFTOVERS+=("$1")
}

# Точка расширения пользователя (*.local) — сообщаем, что не трогаем.
# Попадает и в план (видно до подтверждения), и в итоговое "осталось":
# файл создала установка, значит после удаления он остаётся на машине, а
# отчёт обязан перечислять всё оставшееся, а не только пакеты.
uninstall::_keep() {
  [ -e "$1" ] || return 0
  log::info "  не трогаю $1 — $2"
  uninstall::_leftover "$1 — $2, не трогаю"$'\n'"    удалить, если не нужен: rm -f $1"
}

# Варианты _add с проверкой "а есть ли что делать": план должен читаться
# как список изменений, а не как перечень всех мыслимых путей проекта,
# половина которых на этой машине не существует.
uninstall::_add_rmdir_empty() {
  [ -d "$1" ] && uninstall::_add rmdir_empty "$1"
  return 0
}

uninstall::_add_rcblock() {
  [ -f "$1" ] && grep -qF "# >>> knrc:${2} >>>" "$1" && uninstall::_add rcblock "$1" "$2"
  return 0
}

# --- Опознание "наших" файлов и бэкапов -------------------------------

# Все бэкапы файла, от старого к новому. Схема имени общая для всех
# модулей: <путь>.bak.<YYYYMMDDHHMMSS>, поэтому лексикографический
# порядок глоба совпадает с хронологическим.
uninstall::_backups() {
  local dest="$1" b
  for b in "$dest".bak.*; do
    [ -e "$b" ] || continue
    printf '%s\n' "$b"
  done
}

uninstall::_latest_backup() {
  uninstall::_backups "$1" | tail -n1
}

# Файл всё ещё наш? Либо побайтово совпадает с версией из репозитория
# (обычный случай), либо содержит маркер — на случай, когда репозиторий
# успел обновиться после установки и файл на диске отстал от config/.
uninstall::_is_ours() {
  local dest="$1" src="$2" marker="$3"

  if [ -n "$src" ] && [ -f "$src" ] && command -v cmp >/dev/null 2>&1; then
    cmp -s "$src" "$dest" && return 0
  fi
  if [ -n "$marker" ] && grep -qF "$marker" "$dest" 2>/dev/null; then
    return 0
  fi
  return 1
}

# uninstall::_plan_config <куда-ставили> <исходник-в-репо|""> <маркер>
# Общий откат для всех конфигов, которые install копирует на место:
# вернуть бэкап, либо удалить, либо не трогать чужое.
uninstall::_plan_config() {
  local dest="$1" src="$2" marker="$3" backup rest

  [ -e "$dest" ] || return 0

  if ! uninstall::_is_ours "$dest" "$src" "$marker"; then
    uninstall::_leftover "$dest — файл на месте, но это уже не версия .knrc (правлен вручную?) — не трогаю"
    return 0
  fi

  backup="$(uninstall::_latest_backup "$dest")"
  if [ -n "$backup" ]; then
    uninstall::_add restore "$dest" "$backup"
  else
    uninstall::_add rm "$dest"
  fi

  # Старые бэкапы от предыдущих прогонов install.sh — тоже наши файлы,
  # но удалять их молча нельзя: это единственная копия того, что было на
  # машине раньше. Сообщаем.
  rest="$(uninstall::_backups "$dest" | grep -vxF "${backup:-}" | tr '\n' ' ')"
  if [ -n "${rest// /}" ]; then
    uninstall::_leftover "старые бэкапы $dest: ${rest% }"$'\n'"    удалить: rm -f ${rest% }"
  fi
}

# --- Пакеты: реестр и проверка установленного -------------------------

# Проверка вынесена из _have_jq в отдельный шаг, который uninstall::run
# делает ОДИН раз до планирования. Иначе не работает ни запоминание, ни
# однократность предупреждения: _have_jq зовут функции, которые сами
# вызываются в подстановке команд `$(...)`, то есть в подоболочке —
# присваивание там теряется, и предупреждение печаталось на каждый пакет
# (ловили при тестировании: четыре десятка одинаковых строк).
uninstall::_check_jq() {
  if command -v jq >/dev/null 2>&1; then
    UNINSTALL_HAVE_JQ=1
    return 0
  fi
  UNINSTALL_HAVE_JQ=0
  log::warn "uninstall: нет jq — имена системных пакетов из data/packages/ прочитать нечем"
  uninstall::_leftover "jq не установлен: список пакетов из реестра data/packages/ в отчёте неполон — поставьте jq и повторите 'knrc uninstall --dry-run', чтобы увидеть его целиком"
}

uninstall::_have_jq() {
  [ "$UNINSTALL_HAVE_JQ" = "1" ]
}

# Имя пакета в текущем пакетном менеджере (data/packages/methods/pkg.json).
uninstall::_registry_syspkg() {
  uninstall::_have_jq || return 1
  local value
  value="$(jq -r --arg n "$1" --arg pm "${PKG_MANAGER:-}" \
    '.[$n][$pm] // empty' "$UNINSTALL_REGISTRY_DIR/methods/pkg.json" 2>/dev/null)"
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

# Имя бинарника, который github-метод кладёт в /usr/local/bin
# (data/packages/methods/github.json).
uninstall::_registry_github_target() {
  uninstall::_have_jq || return 1
  local value
  value="$(jq -r --arg n "$1" '.[$n].target_name // empty' \
    "$UNINSTALL_REGISTRY_DIR/methods/github.json" 2>/dev/null)"
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

uninstall::_pkg_installed() {
  local status
  case "${PKG_MANAGER:-}" in
    apt)
      status="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" || return 1
      grep -q '^install ok installed' <<<"$status"
      ;;
    # --whatprovides обязателен вторым шагом: часть имён, которыми мы
    # просим пакет, на rhel-семействе предоставляет пакет с другим
    # именем (на Fedora `wget` приходит из wget2-wget, `vim` — из
    # vim-enhanced), и один только `rpm -q wget` их не видит. Без этого
    # отчёт "осталось в системе" молча недосчитывался бы пакетов —
    # поймано при тестировании на fedora. Удалять их можно по тому же
    # имени: dnf разрешает его через provides.
    dnf|yum)
      rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

uninstall::_pkg_remove_cmd() {
  case "${PKG_MANAGER:-}" in
    # purge, а не remove: у apt `remove` оставляет конфиги пакета.
    apt) echo "sudo apt-get purge -y $*" ;;
    dnf) echo "sudo dnf remove -y $*" ;;
    yum) echo "sudo yum remove -y $*" ;;
    *)   echo "(пакетный менеджер не определён — удалите вручную: $*)" ;;
  esac
}

# uninstall::_leftover_pkgs <что это> <системное-имя...>
# В отчёт попадают только реально установленные пакеты: список из
# полутора десятков имён, половины которых на машине нет, читать
# невозможно, а значит и не будут.
uninstall::_leftover_pkgs() {
  local label="$1"
  shift
  local installed=() p
  for p in "$@"; do
    [ -n "$p" ] || continue
    if uninstall::_pkg_installed "$p"; then
      installed+=("$p")
    fi
  done
  [ "${#installed[@]}" -gt 0 ] || return 0
  uninstall::_leftover "$label: ${installed[*]}"$'\n'"    удалить: $(uninstall::_pkg_remove_cmd "${installed[@]}")"
}

# Пакеты из реестра data/packages: бинарник в /usr/local/bin положили мы
# сами (github-метод) — его удаляем; всё, что пришло из пакетного
# менеджера, идёт в "осталось". Пакетный менеджер кладёт бинарники в
# /usr/bin, так что путь однозначно указывает на источник.
uninstall::_plan_registry_packages() {
  local label="$1"
  shift
  local pkg target syspkg syspkgs=()
  for pkg in "$@"; do
    if target="$(uninstall::_registry_github_target "$pkg")" \
      && [ -e "/usr/local/bin/$target" ]; then
      uninstall::_add sudo_rm "/usr/local/bin/$target"
    fi
    if syspkg="$(uninstall::_registry_syspkg "$pkg")"; then
      syspkgs+=("$syspkg")
    fi
  done
  [ "${#syspkgs[@]}" -gt 0 ] && uninstall::_leftover_pkgs "$label" "${syspkgs[@]}"
  return 0
}

# --- План по модулям --------------------------------------------------

uninstall::plan_base() {
  uninstall::_section "base"
  log::info "  пакетов не удаляю (см. итоговый список)"
  uninstall::_leftover_pkgs "пакеты модуля base" \
    git curl wget vim htop btop tree unzip zip diffutils
  if [ "${OS_FAMILY:-}" = "rhel" ] && uninstall::_pkg_installed epel-release; then
    uninstall::_leftover "репозиторий EPEL (пакет epel-release) остаётся включённым"$'\n'"    удалить: $(uninstall::_pkg_remove_cmd epel-release)"
  fi
}

uninstall::plan_zsh() {
  uninstall::_section "zsh"

  uninstall::_plan_config "$HOME/.zshrc" "$UNINSTALL_DIR/config/zshrc" "Managed by .knrc"
  uninstall::_keep "$HOME/.zshrc.local" "это ваш файл (точка расширения)"

  # powerlevel10k и внешние плагины лежат внутри ~/.oh-my-zsh/custom,
  # отдельными действиями их удалять не нужно.
  [ -d "$HOME/.oh-my-zsh" ] && uninstall::_add rmtree "$HOME/.oh-my-zsh"

  # Кэши, которые создают именно наши плагины и без них бесполезны:
  # gitstatusd — бинарник, который powerlevel10k скачивает себе сам
  # (десятки мегабайт), fsh — тема fast-syntax-highlighting.
  [ -d "$HOME/.cache/gitstatus" ] && uninstall::_add rmtree "$HOME/.cache/gitstatus"
  [ -d "$HOME/.cache/fsh" ] && uninstall::_add rmtree "$HOME/.cache/fsh"

  uninstall::_plan_login_shell

  uninstall::_leftover_pkgs "пакет модуля zsh" zsh
  [ -f "$HOME/.p10k.zsh" ] && uninstall::_leftover "$HOME/.p10k.zsh — ответы мастера 'p10k configure', ваши, не трогаю"$'\n'"    удалить: rm -f $HOME/.p10k.zsh"
  [ -e "$HOME/.zsh_history" ] && uninstall::_leftover "$HOME/.zsh_history — история команд, ваша, не трогаю"
  # Кэши самого zsh, а не наших плагинов: если zsh остаётся на машине,
  # они ему ещё пригодятся (и пересоздаются сами) — поэтому в список, а
  # не в удаление.
  if [ -d "$HOME/.zsh/cache" ] || compgen -G "$HOME/.zcompdump*" >/dev/null; then
    uninstall::_leftover "кэши zsh: $HOME/.zsh/cache, $HOME/.zcompdump* — пересоздаются сами при следующем запуске zsh"$'\n'"    удалить: rm -rf $HOME/.zsh $HOME/.zcompdump*"
  fi
  return 0
}

# Смена login-shell — единственное изменение, которое нельзя откатить,
# посмотрев на систему: в passwd видно только "сейчас zsh". Возвращаем
# ровно то, что модуль zsh записал перед chsh (см. scripts/lib/state.sh),
# и ничего не делаем, если записи нет — на такой машине zsh мог стоять
# login-shell'ом и до нас.
uninstall::_plan_login_shell() {
  local user current prev
  user="$(id -un)"
  current="$(getent passwd "$user" 2>/dev/null | cut -d: -f7)"

  [ -n "$current" ] || return 0
  [ "$(basename "$current")" = "zsh" ] || return 0

  if prev="$(state::read login-shell.prev)" && [ -n "$prev" ]; then
    if [ -x "$prev" ]; then
      uninstall::_add chsh "$prev"
      uninstall::_add state_forget "login-shell.prev"
    else
      uninstall::_leftover "прежний login-shell '$prev' записан, но его нет на машине — login-shell остаётся zsh"$'\n'"    вернуть вручную: chsh -s /bin/bash $user"
    fi
    return 0
  fi

  uninstall::_leftover "login-shell пользователя $user — zsh, но записи о прежнем нет (машина настроена версией .knrc без записи состояния) — не меняю, чтобы не сломать окружение"$'\n'"    вернуть вручную: chsh -s /bin/bash $user"
}

uninstall::plan_tmux() {
  uninstall::_section "tmux"

  uninstall::_plan_config "$HOME/.tmux.conf" "$UNINSTALL_DIR/config/tmux.conf" "Managed by .knrc"
  uninstall::_keep "$HOME/.tmux.conf.local" "это ваш файл (точка расширения)"

  # Удаляем только то, что ставили сами: TPM и три плагина из нашего
  # tmux.conf. Чужие плагины в ~/.tmux/plugins не трогаем, поэтому
  # каталог удаляется только если опустел.
  local plugin
  for plugin in tpm tmux-resurrect tmux-continuum tmux-yank; do
    [ -d "$HOME/.tmux/plugins/$plugin" ] && uninstall::_add rmtree "$HOME/.tmux/plugins/$plugin"
  done
  uninstall::_add_rmdir_empty "$HOME/.tmux/plugins"
  uninstall::_add_rmdir_empty "$HOME/.tmux"

  uninstall::_plan_config "$UNINSTALL_STATE_DIR/tmux-autoattach.sh" \
    "$UNINSTALL_DIR/config/tmux-autoattach.sh" ".knrc"
  uninstall::_add_rcblock "$HOME/.bashrc" "tmux-autoattach"

  uninstall::_leftover_pkgs "пакеты модуля tmux" tmux xclip wl-clipboard
  [ -d "$HOME/.tmux/resurrect" ] && uninstall::_leftover "$HOME/.tmux/resurrect — сохранённые сессии tmux-resurrect, ваши данные, не трогаю"
  return 0
}

uninstall::plan_nvim() {
  uninstall::_section "nvim"

  # Всё, что nvim насоздавал вокруг себя — плагины lazy.nvim, парсеры
  # treesitter, скомпилированный luac-кэш, lazy-lock.json — существует
  # ТОЛЬКО потому, что мы положили свой init.lua. Поэтому удаление этих
  # каталогов привязано к одному вопросу: наш ли ещё init.lua. Если
  # пользователь заменил конфиг своим, всё это уже его хозяйство, и
  # трогать его нельзя — тот же принцип, что и для самих конфигов.
  local init="$HOME/.config/nvim/init.lua" ours=0
  if [ -e "$init" ] \
    && uninstall::_is_ours "$init" "$UNINSTALL_DIR/config/nvim/init.lua" "Managed by .knrc"; then
    ours=1
  fi

  uninstall::_plan_config "$init" "$UNINSTALL_DIR/config/nvim/init.lua" "Managed by .knrc"

  # lazy-lock.json генерирует lazy.nvim из нашего же init.lua: без него
  # файл бессмыслен, а с ним каталог ~/.config/nvim никогда не опустеет.
  if [ "$ours" -eq 1 ] && [ -f "$HOME/.config/nvim/lazy-lock.json" ]; then
    uninstall::_add rm "$HOME/.config/nvim/lazy-lock.json"
  fi
  uninstall::_add_rmdir_empty "$HOME/.config/nvim"

  # Модуль распаковывает релизный архив целиком в /usr/local (bin/ +
  # lib/ + share/). Точного списка файлов не сохранялось, поэтому
  # удаляем три пути, которые заведомо принадлежат только neovim;
  # остальное (man-страницы, .desktop, иконки) — в "осталось".
  if [ -e /usr/local/bin/nvim ]; then
    uninstall::_add sudo_rm /usr/local/bin/nvim
    [ -d /usr/local/lib/nvim ] && uninstall::_add sudo_rmtree /usr/local/lib/nvim
    [ -d /usr/local/share/nvim ] && uninstall::_add sudo_rmtree /usr/local/share/nvim
    uninstall::_leftover "из релизного архива neovim в /usr/local могли остаться man-страницы и .desktop-файл (точный список установки не сохранялся)"$'\n'"    найти: ls /usr/local/share/man/man1/nvim.1 /usr/local/share/applications/nvim.desktop /usr/local/share/icons/hicolor/*/apps/nvim.png 2>/dev/null"
  elif command -v nvim >/dev/null 2>&1; then
    uninstall::_leftover "nvim ($(command -v nvim)) поставлен не нами (не /usr/local/bin) — не трогаю"
  fi

  if [ "$ours" -eq 1 ]; then
    # Плагины lazy.nvim и парсеры treesitter — скачаны и собраны по
    # нашему init.lua.
    [ -d "$HOME/.local/share/nvim/lazy" ] && uninstall::_add rmtree "$HOME/.local/share/nvim/lazy"
    local parser
    for parser in "$HOME/.local/share/nvim"/tree-sitter-*; do
      [ -d "$parser" ] && uninstall::_add rmtree "$parser"
    done
    # ~/.cache/nvim — скомпилированный luac-кэш тех же плагинов (сотни
    # файлов). Чистый кэш: nvim пересоздаёт его сам, терять там нечего.
    [ -d "$HOME/.cache/nvim" ] && uninstall::_add rmtree "$HOME/.cache/nvim"
    uninstall::_add_rmdir_empty "$HOME/.local/share/nvim"
  fi

  # ~/.local/state/nvim — не кэш: там shada (метки, регистры, история
  # команд и открытых файлов). Это результат работы пользователя, а не
  # нашей установки, и переживает смену конфига — только сообщаем.
  [ -d "$HOME/.local/state/nvim" ] && uninstall::_leftover "$HOME/.local/state/nvim — состояние nvim (shada: метки, регистры, история), ваши данные, не трогаю"$'\n'"    удалить: rm -rf $HOME/.local/state/nvim"

  uninstall::_leftover_pkgs "пакет, поставленный ради сборки парсеров treesitter" gcc
  return 0
}

uninstall::plan_aliases() {
  uninstall::_section "aliases"
  uninstall::_plan_config "$UNINSTALL_STATE_DIR/aliases.sh" \
    "$UNINSTALL_DIR/config/aliases.sh" ".knrc"
  uninstall::_keep "$UNINSTALL_STATE_DIR/aliases.local.sh" "это ваш файл (точка расширения)"
  uninstall::_add_rcblock "$HOME/.bashrc" "aliases"
}

uninstall::plan_cli_tools() {
  uninstall::_section "cli-tools"

  uninstall::_plan_registry_packages "пакеты модуля cli-tools" "${CLI_PACKAGES[@]}"

  # httpie ставится pip-методом, только если пакета нет в репозиториях.
  # Одного `pip3 show httpie` мало: pip видит и системный пакет из
  # dist-packages, а попытка снять его через pip на Debian/Ubuntu падает
  # (PEP 668, externally-managed-environment) — ловили ровно это при
  # тестировании. Признак нашей установки — Location внутри $HOME, туда
  # кладёт `pip3 install --user`.
  local location
  if command -v pip3 >/dev/null 2>&1; then
    location="$(pip3 show httpie 2>/dev/null | sed -n 's/^Location: //p')"
    case "$location" in
      "$HOME"/*) uninstall::_add pipuninstall httpie ;;
    esac
  fi

  uninstall::_plan_config "$HOME/.config/bat/config" "$UNINSTALL_DIR/config/bat.conf" ".knrc"
  uninstall::_add_rmdir_empty "$HOME/.config/bat"
}

uninstall::plan_git_ecosystem() {
  uninstall::_section "git-ecosystem"
  log::info "  пакетов не удаляю (см. итоговый список)"

  uninstall::_leftover_pkgs "пакет модуля git-ecosystem" gh

  # gh ставится из собственного репозитория GitHub — он остаётся
  # подключённым и после удаления пакета.
  local f
  for f in /etc/apt/sources.list.d/github-cli.list /etc/yum.repos.d/gh-cli.repo; do
    [ -e "$f" ] && uninstall::_leftover "репозиторий gh подключён: $f"$'\n'"    удалить: sudo rm -f $f /etc/apt/keyrings/githubcli-archive-keyring.gpg"
  done
  return 0
}

uninstall::plan_git_config() {
  uninstall::_section "git-config"

  if ! command -v git >/dev/null 2>&1; then
    log::info "  git не найден — снимать нечего"
    return 0
  fi

  # Снимаем только ключи со СВОИМ значением: если пользователь поменял
  # pull.rebase после установки, это уже его настройка, а не наша.
  local pair key want have
  for pair in "${GIT_CONFIG_DEFAULTS[@]}" "${GIT_CONFIG_PAGER[@]}" "${GIT_CONFIG_EDITOR[@]}"; do
    key="${pair%%=*}"
    want="${pair#*=}"
    have="$(git config --global --get "$key" 2>/dev/null)" || continue
    if [ "$have" = "$want" ]; then
      uninstall::_add gitunset "$key"
    elif [ -n "$have" ]; then
      uninstall::_leftover "git $key = '$have' — значение не наше ('$want'), не трогаю"
    fi
  done

  want="$(git_config::excludes_value)"
  have="$(git config --global --get core.excludesFile 2>/dev/null)"
  if [ "$have" = "$want" ]; then
    uninstall::_add gitunset core.excludesFile
  elif [ -n "$have" ]; then
    uninstall::_leftover "git core.excludesFile = '$have' — значение не наше, не трогаю"
  fi

  uninstall::_plan_config "$UNINSTALL_STATE_DIR/gitignore_global" \
    "$UNINSTALL_DIR/config/gitignore_global" ".knrc"

  # user.name/user.email install.sh только спрашивает — это данные
  # пользователя, снимать их нельзя ни при каких условиях.
  if git config --global --get user.email >/dev/null 2>&1; then
    uninstall::_leftover "git user.name/user.email не трогаю — это ваши данные, а не настройка .knrc"
  fi
  uninstall::_leftover "$HOME/.gitconfig остаётся на месте (могут остаться пустые секции вида [core] — безвредны)"
  return 0
}

uninstall::plan_ssh_config() {
  uninstall::_section "ssh-config"
  local file="$HOME/.ssh/config"
  if [ ! -f "$file" ]; then
    log::info "  $file отсутствует — убирать нечего"
    return 0
  fi
  uninstall::_add_rcblock "$file" "ssh-config"
  # Файла могло не быть до нас — его создал `touch` в ssh_config::install.
  uninstall::_add rm_if_empty "$file"
  # И самого каталога тоже: его создаёт `mkdir -p` в том же модуле.
  # Опустеет он только если ключей в нём нет — с ключами rmdir не сработает.
  uninstall::_add_rmdir_empty "$HOME/.ssh"
}

uninstall::plan_docker() {
  uninstall::_section "docker"

  local user
  user="$(id -un)"
  if state::read docker-group.added >/dev/null 2>&1; then
    local groups
    groups="$(id -nG "$user" 2>/dev/null)"
    if [[ " $groups " == *" docker "* ]]; then
      uninstall::_add dockergroup "$user"
    fi
    uninstall::_add state_forget "docker-group.added"
  elif command -v docker >/dev/null 2>&1; then
    log::info "  группу docker не трогаю — записи о том, что её добавляли мы, нет"
  fi

  if command -v docker >/dev/null 2>&1; then
    uninstall::_leftover "docker остаётся установленным (ставился официальным скриптом get.docker.com)"$'\n'"    удалить: $(uninstall::_pkg_remove_cmd docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)"$'\n'"    данные образов/томов: sudo rm -rf /var/lib/docker /var/lib/containerd"
  fi
  return 0
}

uninstall::plan_python_tools() {
  uninstall::_section "python-tools"

  # Порядок важен: ruff ставился через `uv tool install`, снять его тем
  # же способом можно только пока uv на месте.
  local tools
  if command -v uv >/dev/null 2>&1; then
    tools="$(uv tool list 2>/dev/null)"
    if grep -q '^ruff' <<<"$tools"; then
      uninstall::_add uvtool ruff
    fi
  elif [ -e "$UNINSTALL_LOCALBIN/ruff" ]; then
    uninstall::_add rm "$UNINSTALL_LOCALBIN/ruff"
  fi

  # Резервный метод установки ruff — бинарник с GitHub Releases в
  # /usr/local/bin, к uv отношения не имеет.
  local target
  if target="$(uninstall::_registry_github_target ruff)" && [ -e "/usr/local/bin/$target" ]; then
    uninstall::_add sudo_rm "/usr/local/bin/$target"
  fi

  # uv ставился официальным инсталлером с UV_INSTALL_DIR=~/.local/bin
  # (см. data/packages/methods/curl-sh.json) — удаляем ровно то, что он
  # туда кладёт.
  local f
  for f in uv uvx; do
    [ -e "$UNINSTALL_LOCALBIN/$f" ] && uninstall::_add rm "$UNINSTALL_LOCALBIN/$f"
  done
  # Квитанция установщика uv. Удаляем именно файл, а не весь
  # ~/.config/uv: рядом может лежать пользовательский uv.toml, который к
  # нашей установке отношения не имеет.
  [ -f "$HOME/.config/uv/uv-receipt.json" ] && uninstall::_add rm "$HOME/.config/uv/uv-receipt.json"
  uninstall::_add_rmdir_empty "$HOME/.config/uv"
  [ -d "$HOME/.local/share/uv" ] && uninstall::_add rmtree "$HOME/.local/share/uv"
  [ -d "$HOME/.cache/uv" ] && uninstall::_add rmtree "$HOME/.cache/uv"
  return 0
}

uninstall::plan_extras() {
  uninstall::_section "extras"
  uninstall::_plan_registry_packages "пакеты модуля extras" "${EXTRAS_PACKAGES[@]}"
}

uninstall::plan_diagnostics() {
  uninstall::_section "diagnostics"
  uninstall::_plan_registry_packages "пакеты модуля diagnostics" "${DIAGNOSTICS_PACKAGES[@]}"
}

uninstall::plan_fonts() {
  uninstall::_section "fonts"
  local dir removed=0
  for dir in JetBrainsMonoNerdFont FiraCodeNerdFont; do
    if [ -d "$HOME/.local/share/fonts/$dir" ]; then
      uninstall::_add rmtree "$HOME/.local/share/fonts/$dir"
      removed=1
    fi
  done
  # Без обновления кэша fontconfig удалённый шрифт продолжает
  # предлагаться приложениям — файлов уже нет, а список ещё есть.
  if [ "$removed" -eq 1 ] && command -v fc-cache >/dev/null 2>&1; then
    uninstall::_add fccache
  fi
  uninstall::_add_rmdir_empty "$HOME/.local/share/fonts"
  uninstall::_leftover_pkgs "пакеты, поставленные модулем fonts" unzip fontconfig
}

uninstall::plan_zsh_terminal_app() {
  uninstall::_section "zsh-terminal-app"

  local desktop="$HOME/.local/share/applications/$ZSH_TERMINAL_APP_DESKTOP_ID"
  [ -f "$desktop" ] && uninstall::_add rm "$desktop"

  command -v gsettings >/dev/null 2>&1 || return 0

  # Ищем слот, который создавал модуль — по имени "Zsh Terminal".
  # Верхняя граница нужна: слоты нумеруются подряд и без неё цикл по
  # несуществующим customN бесконечен.
  local base="org.gnome.settings-daemon.plugins.media-keys"
  local list_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
  local i=0 path name
  while [ "$i" -lt 20 ]; do
    path="${list_path}custom${i}/"
    name="$(gsettings get "${base}.custom-keybinding:${path}" name 2>/dev/null)"
    if [ "$name" = "'Zsh Terminal'" ]; then
      uninstall::_add gsettings_unbind "$path"
      return 0
    fi
    i=$((i + 1))
  done
  return 0
}

# Ядро: то, что install.sh ставит всегда, независимо от набора модулей.
# Планируется последним — удаление каталога состояния должно случиться
# после того, как модули из него всё прочитали.
uninstall::plan_core() {
  uninstall::_section "ядро knrc (лаунчер, PATH, состояние)"

  local launcher="$UNINSTALL_LOCALBIN/knrc"
  if [ -e "$launcher" ]; then
    if grep -qF "Managed by .knrc" "$launcher" 2>/dev/null; then
      uninstall::_add rm "$launcher"
    else
      uninstall::_leftover "$launcher — не похож на лаунчер .knrc, не трогаю"
    fi
  fi

  uninstall::_plan_config "$UNINSTALL_STATE_DIR/path.sh" "" "Managed by .knrc"
  uninstall::_add_rcblock "$HOME/.bashrc" "localbin-path"
  # Маркер до переименования (см. localbin::ensure_path) — на машинах,
  # настроенных старой версией, в ~/.bashrc может лежать он.
  uninstall::_add_rcblock "$HOME/.bashrc" "python-tools-path"

  [ -f "$UNINSTALL_RUN_LOG" ] && uninstall::_add rm "$UNINSTALL_RUN_LOG"

  # Каталог состояния целиком, а не rmdir по пустоте: plan_core
  # выполняется только при полном откате, а записи состояния читаются на
  # фазе ПЛАНА — к моменту выполнения они уже никому не нужны. Иначе
  # запись, до которой не дошло дело (например login-shell записан, но
  # пользователь успел сменить shell сам, и откат его не трогал),
  # осталась бы висеть вместе с каталогом.
  [ -d "${UNINSTALL_STATE_DIR}/state" ] && uninstall::_add rmtree "${UNINSTALL_STATE_DIR}/state"
  uninstall::_add_rmdir_empty "$UNINSTALL_STATE_DIR"
  uninstall::_add_rmdir_empty "$UNINSTALL_LOCALBIN"

  uninstall::_leftover "каталог репозитория $UNINSTALL_DIR не удаляю — из него выполняется этот код"$'\n'"    удалить после выхода: rm -rf $UNINSTALL_DIR"
  return 0
}

uninstall::_plan_module() {
  case "$1" in
    base)             uninstall::plan_base ;;
    zsh)              uninstall::plan_zsh ;;
    tmux)             uninstall::plan_tmux ;;
    nvim)             uninstall::plan_nvim ;;
    aliases)          uninstall::plan_aliases ;;
    cli-tools)        uninstall::plan_cli_tools ;;
    git-ecosystem)    uninstall::plan_git_ecosystem ;;
    git-config)       uninstall::plan_git_config ;;
    ssh-config)       uninstall::plan_ssh_config ;;
    docker)           uninstall::plan_docker ;;
    python-tools)     uninstall::plan_python_tools ;;
    extras)           uninstall::plan_extras ;;
    diagnostics)      uninstall::plan_diagnostics ;;
    fonts)            uninstall::plan_fonts ;;
    zsh-terminal-app) uninstall::plan_zsh_terminal_app ;;
  esac
}

# --- Выполнение -------------------------------------------------------

uninstall::_exec_one() {
  local -a f=()
  IFS=$'\t' read -r -a f <<<"$1"

  case "${f[0]}" in
    # mv, а не cp: после возврата бэкап перестаёт быть бэкапом. Побочный
    # эффект намеренный — повторный `knrc uninstall` увидит на месте
    # конфига пользовательский файл без нашего маркера и не тронет его
    # (см. uninstall::_is_ours).
    restore)      mv -f "${f[2]}" "${f[1]}" ;;
    rm)           rm -f "${f[1]}" ;;
    sudo_rm)      sudo rm -f "${f[1]}" ;;
    rmtree)       rm -rf "${f[1]}" ;;
    sudo_rmtree)  sudo rm -rf "${f[1]}" ;;
    # Непустой каталог — не ошибка: значит там осталось пользовательское.
    rmdir_empty)  rmdir "${f[1]}" 2>/dev/null; return 0 ;;
    rm_if_empty)
      if [ -f "${f[1]}" ] && [ -z "$(tr -d '[:space:]' < "${f[1]}")" ]; then
        rm -f "${f[1]}"
      fi
      ;;
    rcblock)      rcfile::remove_block "${f[1]}" "${f[2]}" ;;
    gitunset)     git config --global --unset "${f[1]}" ;;
    chsh)         sudo chsh -s "${f[1]}" "$(id -un)" ;;
    dockergroup)  sudo gpasswd -d "${f[1]}" docker >/dev/null ;;
    uvtool)       uv tool uninstall "${f[1]}" >/dev/null ;;
    pipuninstall) pip3 uninstall -y "${f[1]}" >/dev/null ;;
    fccache)      fc-cache -f >/dev/null ;;
    state_forget) state::forget "${f[1]}" ;;
    gsettings_unbind) uninstall::_exec_gsettings_unbind "${f[1]}" ;;
    *)
      log::err "uninstall: неизвестное действие в плане: $1"
      return 1
      ;;
  esac
}

uninstall::_exec_gsettings_unbind() {
  local path="$1"
  local base="org.gnome.settings-daemon.plugins.media-keys"
  local key list new

  for key in name command binding; do
    gsettings reset "${base}.custom-keybinding:${path}" "$key" 2>/dev/null
  done

  list="$(gsettings get "$base" custom-keybindings 2>/dev/null)" || return 1
  # Слот убираем из списка вместе с разделителем, в какой бы позиции он
  # ни стоял — иначе останется "[, ]" и gsettings не примет значение.
  new="$(sed -e "s|'${path}', *||" -e "s|, *'${path}'||" -e "s|'${path}'||" <<<"$list")"
  gsettings set "$base" custom-keybindings "$new"
}

uninstall::_execute() {
  uninstall::_section "выполняю"
  local record desc i=0
  while [ "$i" -lt "${#UNINSTALL_ACTIONS[@]}" ]; do
    record="${UNINSTALL_ACTIONS[$i]}"
    i=$((i + 1))
    desc="$(uninstall::_describe "$record")"
    if uninstall::_exec_one "$record"; then
      log::info "$desc — готово"
    else
      UNINSTALL_ERRORS=$((UNINSTALL_ERRORS + 1))
      log::err "$desc — не удалось"
    fi
  done
}

# --- Подтверждение ----------------------------------------------------

# Открыть /dev/tty мало проверить через `[ -r ]`: в контейнере без
# выделенного терминала файл существует и проверку проходит, а открытие
# падает с "No such device or address" (тот же случай разобран в
# modules/git-config.sh).
uninstall::_tty_available() {
  { : < /dev/tty; } 2>/dev/null
}

uninstall::_confirm() {
  if [ "$UNINSTALL_FORCE" = "1" ]; then
    log::warn "uninstall: подтверждение получено флагом --force"
    return 0
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ] || ! uninstall::_tty_available; then
    log::err "uninstall: спросить подтверждение негде (NONINTERACTIVE=1 или нет /dev/tty), а удалять без него не буду"
    log::err "uninstall: посмотреть план — 'knrc uninstall --dry-run'; подтвердить без вопроса — 'knrc uninstall --force'"
    return 1
  fi

  local answer
  echo ""
  log::warn "Выше — полный список того, что будет изменено и удалено."
  # Ответ 'yes' целиком, а не [y/N]: цена случайного нажатия здесь —
  # снесённое окружение, и одной буквы для этого мало.
  read -r -p "$(log::prompt "Продолжить удаление? Введите 'yes' для подтверждения: ")" answer < /dev/tty || answer=""
  if [ "$answer" = "yes" ]; then
    return 0
  fi
  log::info "uninstall: отменено, ничего не изменено"
  return 1
}

# --- Точка входа ------------------------------------------------------

uninstall::_known_modules() {
  # zsh-terminal-app не входит в KNRC_ALL_MODULES (он опциональный и
  # ставится только явно), но удалить его должно быть чем — иначе
  # .desktop-файл и хоткей останутся на машине навсегда.
  echo "${KNRC_ALL_MODULES[*]} zsh-terminal-app"
}

uninstall::_validate_modules() {
  local m known ok all
  all="$(uninstall::_known_modules)"
  for m in "$@"; do
    ok=1
    for known in $all; do
      [ "$m" = "$known" ] && { ok=0; break; }
    done
    if [ "$ok" -ne 0 ]; then
      log::err "uninstall: неизвестный модуль '$m'"
      log::err "uninstall: доступны: $all"
      return 2
    fi
  done
}

uninstall::_usage() {
  cat <<EOF
knrc uninstall — откат установки: вернуть машину к состоянию до install.sh.

  --dry-run         показать план и выйти, ничего не меняя
                    (то же самое даёт DRY_RUN=1)
  --force           не спрашивать подтверждение (для автоматизации;
                    то же самое даёт KNRC_UNINSTALL_FORCE=1)
  --modules=СПИСОК  откатить только эти модули (через запятую или
                    пробел). По умолчанию — все, плюс ядро (лаунчер
                    knrc, PATH-снипет, ~/.knrc.log). С --modules ядро
                    НЕ трогается: частичный откат не должен уносить
                    команду knrc.
                    Доступны: $(uninstall::_known_modules)
  --help            эта справка

Что НЕ удаляется: пакеты пакетного менеджера (могли стоять до нас или
быть нужны системе) — по ним печатается список и готовая команда;
ваши *.local-файлы; каталог репозитория.

Без подтверждения не выполняется: нужен ответ 'yes' на вопрос или
явный --force. NONINTERACTIVE=1 сам по себе подтверждением НЕ считается.

Код возврата: 0 — выполнено, 1 — часть шагов не удалась,
2 — ошибка аргументов, 3 — нет подтверждения (ничего не делалось).
EOF
}

uninstall::_print_leftovers() {
  echo ""
  log::info "=== осталось в системе ==="
  if [ "${#UNINSTALL_LEFTOVERS[@]}" -eq 0 ]; then
    log::info "ничего — всё, что ставил .knrc, удалено или возвращено"
    return 0
  fi
  local i=0
  while [ "$i" -lt "${#UNINSTALL_LEFTOVERS[@]}" ]; do
    log::warn "• ${UNINSTALL_LEFTOVERS[$i]}"
    i=$((i + 1))
  done
}

uninstall::run() {
  local modules="" arg dry_run="${DRY_RUN:-0}" explicit_modules=0
  UNINSTALL_FORCE="${KNRC_UNINSTALL_FORCE:-0}"

  for arg in "$@"; do
    case "$arg" in
      --modules=*) modules="${arg#--modules=}"; explicit_modules=1 ;;
      --dry-run)   dry_run=1 ;;
      --force)     UNINSTALL_FORCE=1 ;;
      --help|-h)   uninstall::_usage; return 0 ;;
      --yes)
        # Осознанно не принимаем: `--yes` у install.sh значит "не
        # задавай вопросов, бери дефолты", и рука тянется передать его
        # и сюда. Дефолт удаления — не удалять.
        log::err "uninstall: '--yes' здесь не подтверждение (это флаг install.sh)"
        log::err "uninstall: используйте '--force', если действительно хотите удалить без вопроса"
        return 2
        ;;
      *)
        log::err "uninstall: неизвестный аргумент '$arg'"
        uninstall::_usage >&2
        return 2
        ;;
    esac
  done

  if [ -z "$modules" ]; then
    modules="${KNRC_ALL_MODULES[*]}"
  fi
  modules="${modules//,/ }"

  # shellcheck disable=SC2086 # список модулей разделён пробелами намеренно
  uninstall::_validate_modules $modules || return 2

  # Имена системных пакетов зависят от менеджера — без детекции отчёт
  # "что осталось" будет неполным, но само удаление файлов от неё не
  # зависит, поэтому неудача не фатальна.
  os::detect 2>/dev/null || log::warn "uninstall: дистрибутив не определён — список оставшихся пакетов будет неполным"
  uninstall::_check_jq

  echo ""
  log::info "uninstall: план отката (ничего ещё не изменено)"
  if [ "$dry_run" = "1" ]; then
    log::warn "uninstall: РЕЖИМ DRY-RUN — изменений не будет"
  fi

  local m
  for m in $modules; do
    uninstall::_plan_module "$m"
  done
  if [ "$explicit_modules" -eq 1 ]; then
    echo ""
    log::info "ядро knrc (лаунчер, PATH-снипет, ~/.knrc.log) не трогаю — задан --modules"
  else
    uninstall::plan_core
  fi

  echo ""
  if [ "${#UNINSTALL_ACTIONS[@]}" -eq 0 ]; then
    log::info "uninstall: удалять нечего — ничего из установленного .knrc не найдено"
    uninstall::_print_leftovers
    return 0
  fi
  log::info "uninstall: всего действий — ${#UNINSTALL_ACTIONS[@]}"

  if [ "$dry_run" = "1" ]; then
    uninstall::_print_leftovers
    echo ""
    log::info "Dry-run завершён, изменений не было. Для реального отката — 'knrc uninstall' без --dry-run."
    return 0
  fi

  uninstall::_confirm || return 3

  uninstall::_execute
  uninstall::_print_leftovers

  echo ""
  log::info "=== итог ==="
  if [ "$UNINSTALL_ERRORS" -gt 0 ]; then
    log::err "uninstall: $UNINSTALL_ERRORS из ${#UNINSTALL_ACTIONS[@]} шагов не удалось — см. строки 'не удалось' выше"
    return 1
  fi
  log::info "uninstall: выполнено шагов — ${#UNINSTALL_ACTIONS[@]}, ошибок нет"
  log::info "Перелогиньтесь (или откройте новый терминал), чтобы изменения shell вступили в силу."
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/uninstall.sh: подключать через source, не запускать напрямую (используй 'knrc uninstall')" >&2
  exit 1
fi
