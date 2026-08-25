#!/usr/bin/env bash
# Диспетчер установки пакетов по декларативному реестру
# data/packages/registry.json + data/packages/methods/{pkg,github,pip,curl-sh}.json
# (см. docs/design/pkg-metadata-json.md — схема и обоснование).
# Не запускать напрямую — подключать через `source` после
# scripts/lib/log.sh, scripts/lib/os-detect.sh, scripts/lib/github-release.sh
# (нужны OS_FAMILY/PKG_MANAGER, os::pkg_install, os::pkg_try_install,
# github_release::install, github_release::arch_rust/arch_go).
#
# Публичная точка входа: pkg::install <name> [--source=TYPE]
#
# Требует `jq` — ставится защитно ниже (pkg_registry::_ensure_jq), т.к.
# модули по архитектуре проекта независимы (DOTFILES_MODULES="cli-tools"
# без "base" — документированный сценарий, см. CLAUDE.md), поэтому нельзя
# полагаться на то, что jq уже поставлен другим модулем.

set -euo pipefail

declare -gA PKG_REGISTRY_DONE=()
declare -gA PKG_REGISTRY_IN_PROGRESS=()

pkg_registry::_dir() {
  echo "${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/data/packages"
}

pkg_registry::_ensure_jq() {
  command -v jq >/dev/null 2>&1 || os::pkg_install jq
}

# Единственная переменная, которая сейчас встречается в env-значениях
# methods/curl-sh.json — $HOME. Простая подстановка строки, без eval —
# если в будущем понадобится больше переменных, добавить явно сюда, а не
# заводить общий eval-based expander ради одной переменной.
pkg_registry::_expand() {
  printf '%s' "${1//\$HOME/$HOME}"
}

# pkg::install <name> [--source=TYPE]
# Перебирает методы пакета в порядке priority (или только указанный через
# --source), пока один не сработает. Если ни один не сработал — печатает
# ссылку на исходники (source_url) как последнюю подсказку для ручной
# установки, сама автоматически из исходников не собирает (см.
# docs/design/pkg-metadata-json.md, почему).
pkg::install() {
  pkg_registry::_ensure_jq

  local name="" want_source="" arg
  for arg in "$@"; do
    case "$arg" in
      --source=*) want_source="${arg#--source=}" ;;
      *) name="$arg" ;;
    esac
  done

  if [ -z "$name" ]; then
    log::err "pkg::install: не передано имя пакета"
    return 1
  fi

  if [ -n "${PKG_REGISTRY_DONE[$name]+set}" ]; then
    return "${PKG_REGISTRY_DONE[$name]}"
  fi
  if [ -n "${PKG_REGISTRY_IN_PROGRESS[$name]+set}" ]; then
    log::err "pkg::install: циклическая зависимость 'requires' на пакете '$name'"
    return 1
  fi
  PKG_REGISTRY_IN_PROGRESS[$name]=1

  local registry pkg_json
  registry="$(pkg_registry::_dir)/registry.json"
  pkg_json="$(jq -c --arg n "$name" '.packages[] | select(.name==$n)' "$registry")"
  if [ -z "$pkg_json" ]; then
    log::err "pkg::install: пакет '$name' не найден в реестре ($registry)"
    unset 'PKG_REGISTRY_IN_PROGRESS[$name]'
    return 1
  fi

  local methods method_count
  if [ -n "$want_source" ]; then
    methods="$(jq -c --arg t "$want_source" '[.methods[] | select(.type==$t)]' <<<"$pkg_json")"
  else
    methods="$(jq -c '.methods | sort_by(.priority)' <<<"$pkg_json")"
  fi
  method_count="$(jq 'length' <<<"$methods")"

  if [ "$method_count" -eq 0 ]; then
    if [ -n "$want_source" ]; then
      log::err "pkg::install: у пакета '$name' нет метода '$want_source'"
    else
      log::err "pkg::install: у пакета '$name' не задано ни одного метода в реестре"
    fi
    unset 'PKG_REGISTRY_IN_PROGRESS[$name]'
    PKG_REGISTRY_DONE[$name]=1
    return 1
  fi

  local i=0 ok=1 method
  while [ "$i" -lt "$method_count" ]; do
    method="$(jq -c ".[$i]" <<<"$methods")"
    if pkg_registry::_run_method "$name" "$method"; then
      ok=0
      break
    fi
    i=$((i + 1))
  done

  unset 'PKG_REGISTRY_IN_PROGRESS[$name]'
  PKG_REGISTRY_DONE[$name]=$ok

  if [ "$ok" -ne 0 ]; then
    local source_url
    source_url="$(jq -r '.source_url' <<<"$pkg_json")"
    log::err "pkg::install: не удалось установить '$name' ни одним известным способом"
    log::err "pkg::install: попробуйте вручную — исходники: $source_url"
  fi
  return "$ok"
}

pkg_registry::_run_method() {
  local name="$1" method="$2" type prereq req

  type="$(jq -r '.type' <<<"$method")"

  prereq="$(jq -r '.prereq // empty' <<<"$method")"
  if [ -n "$prereq" ]; then
    if ! declare -F "$prereq" >/dev/null 2>&1; then
      log::err "pkg::install: prereq '$prereq' для '$name' не объявлен (модуль не подключён?)"
      return 1
    fi
    "$prereq"
  fi

  while IFS= read -r req; do
    req="${req%$'\r'}"
    [ -z "$req" ] && continue
    if ! pkg::install "$req"; then
      log::err "pkg::install: зависимость '$req' (нужна для '$name') не установилась"
      return 1
    fi
  done < <(jq -r '.requires // [] | .[]' <<<"$method")

  case "$type" in
    pkg)     pkg_registry::_run_pkg "$name" ;;
    github)  pkg_registry::_run_github "$name" ;;
    pip)     pkg_registry::_run_pip "$name" ;;
    curl-sh) pkg_registry::_run_curl_sh "$name" ;;
    custom)
      local handler
      handler="$(jq -r '.handler' <<<"$method")"
      pkg_registry::_run_custom "$handler"
      ;;
    *)
      log::err "pkg::install: неизвестный тип метода '$type' для '$name'"
      return 1
      ;;
  esac
}

pkg_registry::_run_pkg() {
  local name="$1" file entry pkg_name
  file="$(pkg_registry::_dir)/methods/pkg.json"
  entry="$(jq -c --arg n "$name" '.[$n] // empty' "$file")"
  if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    log::err "pkg::install: нет записи для '$name' в methods/pkg.json"
    return 1
  fi

  pkg_name="$(jq -r --arg pm "$PKG_MANAGER" '.[$pm] // empty' <<<"$entry")"
  if [ -z "$pkg_name" ]; then
    log::err "pkg::install: для '$name' не задано имя пакета под менеджер '$PKG_MANAGER'"
    return 1
  fi

  os::pkg_try_install "$pkg_name"
}

pkg_registry::_run_github() {
  local name="$1" file entry repo inner_path_glob target_name
  local has_by_arch uname_m regex asset_regex arch_rust arch_go
  file="$(pkg_registry::_dir)/methods/github.json"
  entry="$(jq -c --arg n "$name" '.[$n] // empty' "$file")"
  if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    log::err "pkg::install: нет записи для '$name' в methods/github.json"
    return 1
  fi

  repo="$(jq -r '.repo' <<<"$entry")"
  inner_path_glob="$(jq -r '.inner_path_glob' <<<"$entry")"
  target_name="$(jq -r '.target_name' <<<"$entry")"
  has_by_arch="$(jq -r 'has("asset_by_arch")' <<<"$entry")"

  if [ "$has_by_arch" = "true" ]; then
    uname_m="$(uname -m)"
    regex="$(jq -r --arg a "$uname_m" '.asset_by_arch[$a] // empty' <<<"$entry")"
    if [ -z "$regex" ]; then
      log::err "pkg::install: '$name' (github): нет ассета под архитектуру '$uname_m'"
      return 1
    fi
  else
    asset_regex="$(jq -r '.asset_regex' <<<"$entry")"
    arch_rust="$(github_release::arch_rust)"
    arch_go="$(github_release::arch_go)"
    regex="${asset_regex//\{arch_rust\}/$arch_rust}"
    regex="${regex//\{arch_go\}/$arch_go}"
  fi

  github_release::install "$repo" "$regex" "$inner_path_glob" "$target_name"
}

pkg_registry::_run_pip() {
  local name="$1" file entry pip_name requires_pkg
  file="$(pkg_registry::_dir)/methods/pip.json"
  entry="$(jq -c --arg n "$name" '.[$n] // empty' "$file")"
  if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    log::err "pkg::install: нет записи для '$name' в methods/pip.json"
    return 1
  fi

  pip_name="$(jq -r '.pip_name' <<<"$entry")"
  requires_pkg="$(jq -r '.requires_pkg // empty' <<<"$entry")"

  command -v pip3 >/dev/null 2>&1 || { [ -n "$requires_pkg" ] && os::pkg_install "$requires_pkg"; }

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] установил бы через pip: $pip_name"
    return 0
  fi

  pip3 install --user "$pip_name"
}

pkg_registry::_run_curl_sh() {
  local name="$1" file entry url check_command check_path key val
  file="$(pkg_registry::_dir)/methods/curl-sh.json"
  entry="$(jq -c --arg n "$name" '.[$n] // empty' "$file")"
  if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    log::err "pkg::install: нет записи для '$name' в methods/curl-sh.json"
    return 1
  fi

  url="$(jq -r '.url' <<<"$entry")"
  check_command="$(jq -r '.check.command // empty' <<<"$entry")"
  check_path="$(jq -r '.check.path // empty' <<<"$entry")"
  check_path="$(pkg_registry::_expand "$check_path")"

  if { [ -n "$check_command" ] && command -v "$check_command" >/dev/null 2>&1; } \
    || { [ -n "$check_path" ] && [ -x "$check_path" ]; }; then
    log::info "pkg::install: $name уже установлен, пропускаю"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] запустил бы установщик $url для $name"
    return 0
  fi

  local env_assignments=()
  while IFS= read -r key; do
    key="${key%$'\r'}"
    [ -z "$key" ] && continue
    val="$(jq -r --arg k "$key" '.env[$k]' <<<"$entry")"
    val="$(pkg_registry::_expand "$val")"
    env_assignments+=("$key=$val")
  done < <(jq -r '.env // {} | keys[]' <<<"$entry")

  curl -fsSL "$url" | env "${env_assignments[@]}" sh
}

# custom не хранит технических полей в methods/custom.json — единственная
# деталь (handler) лежит прямо в записи метода в registry.json. custom —
# чёрный ящик: DRY_RUN и идемпотентность не централизованы (handler
# отвечает за них сам), см. docs/design/pkg-metadata-json.md.
pkg_registry::_run_custom() {
  local handler="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log::info "[dry-run] запустил бы custom-обработчик '$handler'"
    return 0
  fi
  if ! declare -F "$handler" >/dev/null 2>&1; then
    log::err "pkg::install: custom handler '$handler' не объявлен (модуль не подключён?)"
    return 1
  fi
  "$handler"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/pkg-registry.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
