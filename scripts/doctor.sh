#!/usr/bin/env bash
# Диагностика состояния машины после install.sh: что встало, чего нет,
# что стоит, но сломано. Только читает — ничего не чинит, не ставит и не
# правит конфиги (это принципиальное ограничение, см. docs/modules/doctor.md).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh, scripts/lib/os-detect.sh и scripts/lib/modules.sh;
# пользовательская точка входа — `knrc doctor` (scripts/knrc.sh).
#
# Публичная точка входа: doctor::run [--modules=LIST] [--help]
#
# Код возврата: 0 — проблем нет; 1 — есть отсутствующее или сломанное
# (годится как шаг CI); 2 — ошибка аргументов.
#
# ВАЖНО: файл сознательно НЕ включает `set -e`. Диагностика обязана
# дойти до конца и напечатать все строки, даже если половина проверок
# возвращает ненулевой код — это её нормальный режим работы, а не сбой.
# Библиотеки, которые doctor подключает, включают `set -e` у себя —
# scripts/knrc.sh снимает его обратно перед вызовом doctor::run.
#
# ВАЖНО-2: при `pipefail` нельзя писать проверки вида
# `команда | grep -q ОБРАЗЕЦ` в условии. `grep -q` выходит на первом же
# совпадении и закрывает пайп, команда слева получает SIGPIPE (141), и
# `pipefail` делает ВЕСЬ конвейер неуспешным — то есть условие ложно
# ровно тогда, когда образец нашёлся. Реально поймали на проверке
# шрифтов (см. docs/modules/doctor.md). Поэтому здесь grep читает из
# here-string (`grep -q ОБРАЗЕЦ <<<"$var"`), а не из пайпа.

set -uo pipefail

DOCTOR_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.config/knrc}"
DOCTOR_ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
DOCTOR_RUN_LOG="$HOME/.knrc.log"

DOCTOR_OK=0
DOCTOR_MISSING=0
DOCTOR_BROKEN=0

# --- Примитивы вывода -------------------------------------------------
#
# Отдельного форматирования у doctor нет: три статуса ложатся ровно на
# три уровня scripts/lib/log.sh (ok -> info, отсутствует -> warn,
# сломано -> err), так что цвет, префикс "[.knrc]" и поведение при
# NO_COLOR/не-терминале наследуются без единой своей ANSI-строки.

doctor::_ok() {
  DOCTOR_OK=$((DOCTOR_OK + 1))
  log::info "$1 — ok${2:+ ($2)}"
}

doctor::_missing() {
  DOCTOR_MISSING=$((DOCTOR_MISSING + 1))
  log::warn "$1 — отсутствует${2:+ ($2)}"
}

doctor::_broken() {
  DOCTOR_BROKEN=$((DOCTOR_BROKEN + 1))
  log::err "$1 — сломано${2:+: $2}"
}

# Строка-контекст, которая не является ни проблемой, ни успехом и не
# влияет на код возврата: осознанный выбор пользователя (zsh не
# login-shell), сведения о системе и т.п.
doctor::_note() {
  log::info "$1 — $2"
}

doctor::_section() {
  echo ""
  log::info "=== $1 ==="
}

# --- Примитивы проверок -----------------------------------------------

# doctor::_bin <label> <команда> [альтернативное имя бинарника]
# Альтернатива — это случай fd/fdfind и bat/batcat на apt: пакет стоит,
# но симлинка нет, значит команда из алиасов/конфигов не сработает.
doctor::_bin() {
  local label="$1" cmd="$2" alt="${3:-}" path
  if path="$(command -v "$cmd" 2>/dev/null)"; then
    doctor::_ok "$label" "$path"
    return 0
  fi
  if [ -n "$alt" ] && path="$(command -v "$alt" 2>/dev/null)"; then
    doctor::_broken "$label" \
      "в PATH только '$alt' ($path), симлинка '$cmd' нет (cli::ensure_symlinks не отработал)"
    return 1
  fi
  doctor::_missing "$label" "'$cmd' не найден в PATH"
  return 1
}

# doctor::_file <label> <путь> [маркер]
# Маркер — подстрока, по которой видно, что файлом управляет .knrc
# ("Managed by .knrc", "# >>> knrc:..."). Файл на месте, но без маркера —
# значит его заменили вручную и install.sh его больше не обновлял.
doctor::_file() {
  local label="$1" path="$2" marker="${3:-}"
  if [ ! -e "$path" ]; then
    doctor::_missing "$label" "$path"
    return 1
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    doctor::_broken "$label" "$path не обычный читаемый файл"
    return 1
  fi
  if [ ! -s "$path" ]; then
    doctor::_broken "$label" "$path пустой"
    return 1
  fi
  if [ -n "$marker" ] && ! grep -qF "$marker" "$path"; then
    doctor::_broken "$label" "$path есть, но без маркера '$marker' — заменён вручную?"
    return 1
  fi
  doctor::_ok "$label" "$path"
  return 0
}

# doctor::_dir <label> <путь> — каталог существует и не пуст. Пустой
# каталог у нас всегда означает оборванный clone/распаковку, а не
# валидное состояние, поэтому это "сломано", а не "отсутствует".
doctor::_dir() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then
    doctor::_missing "$label" "$path"
    return 1
  fi
  if [ ! -d "$path" ]; then
    doctor::_broken "$label" "$path не каталог"
    return 1
  fi
  if [ -z "$(ls -A "$path" 2>/dev/null)" ]; then
    doctor::_broken "$label" "$path пустой — оборванная установка?"
    return 1
  fi
  doctor::_ok "$label" "$path"
  return 0
}

# doctor::_rcblock <label> <rc-файл> <маркер> — управляемый блок
# rcfile::upsert_block на месте.
doctor::_rcblock() {
  local label="$1" file="$2" marker="$3"
  if [ ! -f "$file" ]; then
    doctor::_missing "$label" "нет $file"
    return 1
  fi
  if ! grep -qF "# >>> knrc:${marker} >>>" "$file"; then
    doctor::_missing "$label" "в $file нет блока knrc:${marker}"
    return 1
  fi
  doctor::_ok "$label" "$file"
  return 0
}

# doctor::_syntax <label> <файл> <интерпретатор>
# Проверка синтаксиса конфигов, которые шелл сорсит при старте: битый
# ~/.zshrc или ~/.config/knrc/aliases.sh ломает каждый новый терминал, и
# заметить это по одному только факту "файл на месте" нельзя.
doctor::_syntax() {
  local label="$1" file="$2" interpreter="$3" out
  [ -f "$file" ] || return 0
  if ! command -v "$interpreter" >/dev/null 2>&1; then
    doctor::_note "$label" "пропускаю проверку синтаксиса — нет '$interpreter'"
    return 0
  fi
  if out="$("$interpreter" -n "$file" 2>&1)"; then
    doctor::_ok "$label"
    return 0
  fi
  doctor::_broken "$label" "$(head -n1 <<<"$out")"
  return 1
}

# --- Общесистемные проверки -------------------------------------------

doctor::check_system() {
  doctor::_section "система"

  if os::detect 2>/dev/null; then
    doctor::_note "дистрибутив" "$OS_ID ${OS_VERSION_ID:-?} (family=$OS_FAMILY, pkg=$PKG_MANAGER)"
  else
    doctor::_broken "дистрибутив" "не удалось определить (нет /etc/os-release или он не поддерживается)"
  fi

  doctor::_note "архитектура" "$(uname -m)"

  if [ -f "$DOCTOR_RUN_LOG" ]; then
    doctor::_note "последний прогон install.sh" "$(tail -n1 "$DOCTOR_RUN_LOG")"
  else
    doctor::_missing "лог прогонов ~/.knrc.log" "install.sh на этой машине не запускался?"
  fi
}

# "Где сломался PATH" из постановки задачи: пустой элемент в PATH — это
# молча подключённый текущий каталог (и дыра в безопасности, и источник
# "команда ведёт себя по-разному в разных каталогах"), поэтому единственный
# случай со статусом "сломано". Несуществующие каталоги в PATH безобидны
# (шелл их просто пропускает) — только упоминаем.
doctor::check_path() {
  doctor::_section "PATH"

  local entries=() entry missing_dirs=() i=0
  IFS=: read -r -a entries <<<"$PATH"
  while [ "$i" -lt "${#entries[@]}" ]; do
    entry="${entries[$i]}"
    i=$((i + 1))
    if [ -z "$entry" ]; then
      doctor::_broken "PATH" "содержит пустой элемент — шелл трактует его как текущий каталог"
    elif [ ! -d "$entry" ]; then
      missing_dirs+=("$entry")
    fi
  done

  if [ "${#missing_dirs[@]}" -gt 0 ]; then
    doctor::_note "PATH" "несуществующие каталоги (безвредно, шелл их пропускает): ${missing_dirs[*]}"
  fi

  local dir
  for dir in /usr/local/bin "$HOME/.local/bin"; do
    case ":$PATH:" in
      *":$dir:"*) doctor::_ok "$dir в PATH" ;;
      *) doctor::_missing "$dir в PATH" "туда ставятся бинарники github-release, uv и лаунчер knrc" ;;
    esac
  done
}

doctor::check_launcher() {
  doctor::_section "лаунчер knrc"

  doctor::_file "снипет PATH" "$DOCTOR_STATE_DIR/path.sh" "Managed by .knrc"
  doctor::_rcblock "подключение PATH в ~/.bashrc" "$HOME/.bashrc" "localbin-path"

  local launcher="$HOME/.local/bin/knrc"
  if [ ! -e "$launcher" ]; then
    doctor::_missing "команда knrc" "$launcher"
    return 0
  fi
  if [ ! -x "$launcher" ]; then
    doctor::_broken "команда knrc" "$launcher не исполняемый"
    return 0
  fi

  # Лаунчер — тонкая обёртка, вся логика лежит в репозитории; если
  # репозиторий переехал или удалён, `knrc` останется в PATH, но перестанет
  # работать — самый вероятный способ сломать эту схему.
  local repo
  # shellcheck disable=SC2016 # это sed-скрипт, а не строка для шелла
  repo="$(sed -n 's/^KNRC_REPO_DIR="\${KNRC_REPO_DIR:-\(.*\)}"$/\1/p' "$launcher")"
  repo="${repo%%$'\n'*}"
  if [ -z "$repo" ]; then
    doctor::_broken "команда knrc" "$launcher не похож на лаунчер .knrc"
  elif [ ! -f "$repo/scripts/knrc.sh" ]; then
    doctor::_broken "команда knrc" "ссылается на $repo, но там нет scripts/knrc.sh"
  else
    doctor::_ok "команда knrc" "$launcher -> $repo"
  fi
}

doctor::check_login_shell() {
  doctor::_section "login-shell"

  local user shell
  user="$(id -un)"
  # $SHELL не обновляется до перелогина — смотрим passwd, как это делает
  # zsh::configure_shell.
  shell="$(getent passwd "$user" 2>/dev/null | cut -d: -f7)"

  if [ -z "$shell" ]; then
    doctor::_broken "login-shell пользователя $user" "не удалось прочитать из passwd"
    return 0
  fi
  if [ ! -x "$shell" ]; then
    doctor::_broken "login-shell пользователя $user" "$shell не существует или не исполняемый"
    return 0
  fi
  if [ "$(basename "$shell")" = "zsh" ]; then
    doctor::_ok "login-shell пользователя $user" "$shell"
    return 0
  fi
  # Смена login-shell в проекте опциональна (ZSH_DEFAULT_SHELL), поэтому
  # "не zsh" — это не проблема и не влияет на код возврата.
  doctor::_note "login-shell пользователя $user" \
    "$shell — не zsh (допустимый режим, см. ZSH_DEFAULT_SHELL и модуль zsh-terminal-app)"
}

# --- Проверки по модулям ----------------------------------------------

doctor::check_base() {
  doctor::_section "base"
  local cmd
  for cmd in git curl wget vim htop btop tree unzip zip; do
    doctor::_bin "$cmd" "$cmd"
  done
  # diffutils ставится не ради имени пакета, а ради cmp — им модули
  # сравнивают конфиги перед перезаписью.
  doctor::_bin "cmp (diffutils)" cmp
}

doctor::check_zsh() {
  doctor::_section "zsh"

  doctor::_bin "бинарник zsh" zsh
  doctor::_file "oh-my-zsh" "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  doctor::_dir "тема powerlevel10k" "$DOCTOR_ZSH_CUSTOM/themes/powerlevel10k"

  local plugin
  for plugin in zsh-autosuggestions fast-syntax-highlighting zsh-completions; do
    doctor::_dir "плагин oh-my-zsh $plugin" "$DOCTOR_ZSH_CUSTOM/plugins/$plugin"
  done

  doctor::_file "конфиг ~/.zshrc" "$HOME/.zshrc" "Managed by .knrc"
  doctor::_syntax "синтаксис ~/.zshrc" "$HOME/.zshrc" zsh
  doctor::_file "локальный ~/.zshrc.local" "$HOME/.zshrc.local"

  # ~/.p10k.zsh появляется только после первого интерактивного запуска
  # мастера — отсутствие это нормальное состояние свежей машины.
  if [ -f "$HOME/.p10k.zsh" ]; then
    doctor::_ok "конфиг Powerlevel10k ~/.p10k.zsh"
  else
    doctor::_note "конфиг Powerlevel10k ~/.p10k.zsh" \
      "ещё не создан — мастер 'p10k configure' запустится при первом интерактивном zsh"
  fi
}

doctor::check_tmux() {
  doctor::_section "tmux"

  doctor::_bin "бинарник tmux" tmux
  doctor::_file "конфиг ~/.tmux.conf" "$HOME/.tmux.conf" "Managed by .knrc"
  doctor::_file "локальный ~/.tmux.conf.local" "$HOME/.tmux.conf.local"

  local tpm="$HOME/.tmux/plugins/tpm"
  if [ -x "$tpm/tpm" ]; then
    doctor::_ok "TPM" "$tpm"
  elif [ -d "$tpm" ]; then
    doctor::_broken "TPM" "$tpm есть, но $tpm/tpm не исполняемый — оборванный clone?"
  else
    doctor::_missing "TPM" "$tpm"
  fi

  local plugin
  for plugin in tmux-resurrect tmux-continuum tmux-yank; do
    doctor::_dir "плагин tmux $plugin" "$HOME/.tmux/plugins/$plugin"
  done

  doctor::_file "хук авто-подключения" "$DOCTOR_STATE_DIR/tmux-autoattach.sh" ".knrc"
  doctor::_syntax "синтаксис хука авто-подключения" "$DOCTOR_STATE_DIR/tmux-autoattach.sh" bash
  doctor::_rcblock "подключение хука в ~/.bashrc" "$HOME/.bashrc" "tmux-autoattach"

  # tmux-yank без внешнего инструмента буфера обмена молча не копирует —
  # ставится по-разному (X11/Wayland) и может отсутствовать легально.
  if command -v xclip >/dev/null 2>&1 || command -v wl-copy >/dev/null 2>&1; then
    doctor::_ok "буфер обмена для tmux-yank (xclip/wl-copy)"
  else
    doctor::_missing "буфер обмена для tmux-yank" "нет ни xclip, ни wl-copy — копирование из copy-mode не работает"
  fi
}

doctor::check_nvim() {
  doctor::_section "nvim"

  doctor::_bin "бинарник nvim" nvim || return 0
  doctor::_file "конфиг ~/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua" "Managed by .knrc"

  local lazy_dir="$HOME/.local/share/nvim/lazy"
  doctor::_dir "менеджер плагинов lazy.nvim" "$lazy_dir/lazy.nvim"

  local plugin
  for plugin in tokyonight.nvim nvim-tree.lua lualine.nvim telescope.nvim \
    nvim-treesitter gitsigns.nvim Comment.nvim which-key.nvim indent-blankline.nvim; do
    doctor::_dir "плагин nvim $plugin" "$lazy_dir/$plugin"
  done

  # Единственная настоящая проверка валидности init.lua: загрузить его
  # так же, как это делает реальный запуск, и сразу выйти. Ошибка в
  # конфиге видна только здесь — файл при этом на месте и с маркером.
  # Одного кода возврата мало: при ошибке в lua-конфиге nvim печатает её
  # и всё равно выходит с 0 по '+qa', поэтому смотрим и на вывод.
  local out rc
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout 120 nvim --headless '+qa' 2>&1)"
  else
    out="$(nvim --headless '+qa' 2>&1)"
  fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    doctor::_broken "загрузка конфига nvim" "nvim --headless +qa вернул $rc"
  elif grep -qiE 'error|E[0-9]{2,}:' <<<"$out"; then
    doctor::_broken "загрузка конфига nvim" "$(head -n2 <<<"$out" | tr '\n' ' ')"
  else
    doctor::_ok "загрузка конфига nvim"
  fi
}

doctor::check_aliases() {
  doctor::_section "aliases"
  doctor::_file "снипет алиасов" "$DOCTOR_STATE_DIR/aliases.sh" ".knrc"
  doctor::_syntax "синтаксис снипета алиасов" "$DOCTOR_STATE_DIR/aliases.sh" bash
  doctor::_file "личные алиасы пользователя" "$DOCTOR_STATE_DIR/aliases.local.sh"
  doctor::_rcblock "подключение алиасов в ~/.bashrc" "$HOME/.bashrc" "aliases"
}

doctor::check_cli_tools() {
  doctor::_section "cli-tools"
  doctor::_bin "ripgrep (rg)" rg
  doctor::_bin "fd" fd fdfind
  doctor::_bin "fzf" fzf
  doctor::_bin "bat" bat batcat
  doctor::_bin "eza" eza
  doctor::_bin "zoxide" zoxide
  doctor::_bin "delta" delta
  doctor::_bin "jq" jq
  doctor::_bin "httpie (http)" http
  doctor::_bin "curlie" curlie
  doctor::_bin "direnv" direnv
  doctor::_file "конфиг bat" "$HOME/.config/bat/config"
  doctor::_file "direnvrc (layout_uv)" "$HOME/.config/direnv/direnvrc"
}

doctor::check_git_ecosystem() {
  doctor::_section "git-ecosystem"
  doctor::_bin "gh (GitHub CLI)" gh
}

# Отдельный случай: ключ ссылается на бинарник, которого нет. Такой
# ~/.gitconfig ломает вообще любой `git diff`/`git commit`, а не только
# красивый вывод — именно то, что должен ловить doctor.
#
# doctor::_git_key_binary <ключ> <бинарник> <модуль>
# Незаполненный ключ — проблема только если бинарник в PATH есть:
# git_config::setup_pager/setup_editor намеренно не трогают эти ключи,
# когда delta/nvim не установлены (конфиг со ссылкой на несуществующий
# pager ломает git полностью). Повторять здесь это условие обязательно,
# иначе doctor ругается на машину, где просто не выбран модуль
# cli-tools или nvim — ровно тот ложный сигнал, из-за которого
# диагностику перестают читать.
doctor::_git_key_binary() {
  local key="$1" expected_bin="$2" module="$3" value
  if ! value="$(git config --global --get "$key" 2>/dev/null)" || [ -z "$value" ]; then
    if command -v "$expected_bin" >/dev/null 2>&1; then
      doctor::_missing "git $key" "не выставлен, хотя '$expected_bin' есть в PATH"
    else
      doctor::_note "git $key" \
        "не выставлен — '$expected_bin' не установлен (модуль $module не ставился), это штатное поведение git-config"
    fi
    return 1
  fi
  # Значение может быть командой с аргументами ("delta --color-only").
  local bin="${value%% *}"
  if command -v "$bin" >/dev/null 2>&1; then
    doctor::_ok "git $key" "$value"
    return 0
  fi
  doctor::_broken "git $key" "= '$value', но '$bin' не найден в PATH"
  return 1
}

doctor::check_git_config() {
  doctor::_section "git-config"

  if ! command -v git >/dev/null 2>&1; then
    doctor::_missing "git" "без него ~/.gitconfig проверить нечем"
    return 0
  fi

  local key value
  for key in init.defaultBranch pull.rebase push.autoSetupRemote rerere.enabled diff.algorithm; do
    if value="$(git config --global --get "$key" 2>/dev/null)" && [ -n "$value" ]; then
      doctor::_ok "git $key" "$value"
    else
      doctor::_missing "git $key" "не выставлен"
    fi
  done

  doctor::_git_key_binary core.pager delta cli-tools
  doctor::_git_key_binary core.editor nvim nvim

  local excludes
  if excludes="$(git config --global --get core.excludesFile 2>/dev/null)" && [ -n "$excludes" ]; then
    # В конфиге путь хранится как ~/..., git раскрывает его сам.
    doctor::_file "глобальный gitignore" "${excludes/#\~/$HOME}"
  else
    doctor::_missing "git core.excludesFile" "не выставлен"
  fi

  # user.name/user.email — единственное, что install.sh не может
  # выставить за пользователя; без них не сделать ни одного коммита.
  for key in user.name user.email; do
    if value="$(git config --global --get "$key" 2>/dev/null)" && [ -n "$value" ]; then
      doctor::_ok "git $key" "$value"
    else
      doctor::_missing "git $key" "не заполнен — коммиты делать не получится"
    fi
  done
}

doctor::check_ssh_config() {
  doctor::_section "ssh-config"

  local dir="$HOME/.ssh" file="$HOME/.ssh/config" mode
  if [ ! -d "$dir" ]; then
    doctor::_missing "каталог ~/.ssh" "$dir"
    return 0
  fi

  mode="$(stat -c '%a' "$dir" 2>/dev/null)"
  if [ "$mode" = "700" ]; then
    doctor::_ok "права ~/.ssh" "700"
  else
    # ssh сам отказывается работать с слишком открытыми правами —
    # это не косметика.
    doctor::_broken "права ~/.ssh" "${mode:-?} вместо 700"
  fi

  doctor::_rcblock "блок Host * в ~/.ssh/config" "$file" "ssh-config"

  if [ -f "$file" ]; then
    mode="$(stat -c '%a' "$file" 2>/dev/null)"
    if [ "$mode" = "600" ]; then
      doctor::_ok "права ~/.ssh/config" "600"
    else
      doctor::_broken "права ~/.ssh/config" "${mode:-?} вместо 600"
    fi
  fi
}

doctor::check_docker() {
  doctor::_section "docker"

  doctor::_bin "бинарник docker" docker || return 0

  if docker compose version >/dev/null 2>&1; then
    doctor::_ok "плагин docker compose"
  else
    doctor::_missing "плагин docker compose" "'docker compose version' не отвечает"
  fi

  local user user_groups
  user="$(id -un)"
  user_groups="$(id -nG "$user" 2>/dev/null)"
  if [[ " $user_groups " == *" docker "* ]]; then
    doctor::_note "группа docker" "$user состоит в ней (docker без sudo)"
  else
    doctor::_note "группа docker" "$user не состоит — docker только через sudo (см. DOCKER_ADD_USER_TO_GROUP)"
  fi

  # Демон может быть намеренно остановлен, а в контейнере/WSL без systemd
  # его нет вовсе — это не дефект установки, поэтому note, а не проблема.
  if docker info >/dev/null 2>&1; then
    doctor::_note "демон docker" "отвечает"
  else
    doctor::_note "демон docker" "не отвечает из-под $user (не запущен, нет systemd или нужен sudo)"
  fi
}

doctor::check_python_tools() {
  doctor::_section "python-tools"
  doctor::_bin "uv" uv
  doctor::_bin "ruff" ruff
}

doctor::check_extras() {
  doctor::_section "extras"
  doctor::_bin "tldr" tldr
  doctor::_bin "fastfetch" fastfetch
}

doctor::check_diagnostics() {
  doctor::_section "diagnostics"
  local cmd
  for cmd in rsync dig ncdu lsof mtr; do
    doctor::_bin "$cmd" "$cmd"
  done
}

doctor::check_fonts() {
  doctor::_section "fonts"

  doctor::_dir "JetBrainsMono Nerd Font" "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  doctor::_dir "FiraCode Nerd Font" "$HOME/.local/share/fonts/FiraCodeNerdFont"

  # Файлы на диске и "шрифт доступен приложениям" — разные вещи: без
  # обновлённого кэша fontconfig терминал шрифта не увидит, а иконки
  # Powerlevel10k превратятся в квадраты.
  if ! command -v fc-list >/dev/null 2>&1; then
    doctor::_missing "fontconfig (fc-list)" "нечем проверить, виден ли Nerd Font системе"
    return 0
  fi
  local installed
  installed="$(fc-list 2>/dev/null)"
  if grep -qi 'nerd font' <<<"$installed"; then
    doctor::_ok "Nerd Font виден fontconfig"
  else
    doctor::_missing "Nerd Font виден fontconfig" "шрифт не в кэше — иконки Powerlevel10k не отрисуются"
  fi

  doctor::_note "шрифт в терминале" \
    "выбор Nerd Font в настройках терминального эмулятора автоматизировать нельзя — проверь вручную"
}

# --- Диспетчер --------------------------------------------------------

doctor::_run_module() {
  case "$1" in
    base)          doctor::check_base ;;
    zsh)           doctor::check_zsh ;;
    tmux)          doctor::check_tmux ;;
    nvim)          doctor::check_nvim ;;
    aliases)       doctor::check_aliases ;;
    cli-tools)     doctor::check_cli_tools ;;
    git-ecosystem) doctor::check_git_ecosystem ;;
    git-config)    doctor::check_git_config ;;
    ssh-config)    doctor::check_ssh_config ;;
    docker)        doctor::check_docker ;;
    python-tools)  doctor::check_python_tools ;;
    extras)        doctor::check_extras ;;
    diagnostics)   doctor::check_diagnostics ;;
    fonts)         doctor::check_fonts ;;
  esac
}

# Имена модулей проверяем до первой проверки, а не по ходу: опечатка в
# --modules не должна выясняться на середине уже напечатанного отчёта.
doctor::_validate_modules() {
  local m known ok
  for m in "$@"; do
    ok=1
    for known in "${KNRC_ALL_MODULES[@]}"; do
      [ "$m" = "$known" ] && { ok=0; break; }
    done
    if [ "$ok" -ne 0 ]; then
      log::err "doctor: неизвестный модуль '$m'"
      log::err "doctor: доступны: ${KNRC_ALL_MODULES[*]}"
      return 2
    fi
  done
}

doctor::_usage() {
  cat <<EOF
knrc doctor — диагностика окружения (ничего не чинит и не ставит).

  --modules=СПИСОК  проверить только эти модули (через запятую или
                    пробел). По умолчанию — все: ${KNRC_ALL_MODULES[*]}
  --help            эта справка

Код возврата: 0 — проблем нет, 1 — есть отсутствующее/сломанное,
2 — ошибка аргументов.
EOF
}

doctor::_summary() {
  echo ""
  log::info "=== итог ==="
  log::info "ok: $DOCTOR_OK, отсутствует: $DOCTOR_MISSING, сломано: $DOCTOR_BROKEN"

  if [ "$DOCTOR_BROKEN" -gt 0 ] || [ "$DOCTOR_MISSING" -gt 0 ]; then
    log::warn "doctor: есть проблемы — см. строки со статусом 'отсутствует'/'сломано' выше"
    log::info "doctor: доустановить недостающее — './install.sh' (например DOTFILES_MODULES=\"zsh tmux\" ./install.sh)"
    return 1
  fi
  log::info "doctor: проблем не найдено"
  return 0
}

doctor::run() {
  local modules="" arg
  for arg in "$@"; do
    case "$arg" in
      --modules=*) modules="${arg#--modules=}" ;;
      --help|-h) doctor::_usage; return 0 ;;
      *)
        log::err "doctor: неизвестный аргумент '$arg'"
        doctor::_usage >&2
        return 2
        ;;
    esac
  done

  if [ -z "$modules" ]; then
    modules="${KNRC_ALL_MODULES[*]}"
  fi
  modules="${modules//,/ }"

  # shellcheck disable=SC2086 # список модулей разделён пробелами намеренно
  doctor::_validate_modules $modules || return 2

  doctor::check_system
  doctor::check_path
  doctor::check_launcher
  doctor::check_login_shell

  local m
  for m in $modules; do
    doctor::_run_module "$m"
  done

  doctor::_summary
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/doctor.sh: подключать через source, не запускать напрямую (используй 'knrc doctor')" >&2
  exit 1
fi
