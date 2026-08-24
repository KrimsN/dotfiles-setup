#!/usr/bin/env bash
# Установка бинарников напрямую с GitHub Releases — для инструментов,
# которых нет (или нет везде/во всех актуальных версиях) в стандартных
# репозиториях целевых дистрибутивов.
# Не запускать напрямую — подключать через `source`.

set -euo pipefail

github_release::arch_rust() {
  case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    aarch64|arm64) echo aarch64 ;;
    *) uname -m ;;
  esac
}

github_release::arch_go() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) uname -m ;;
  esac
}

# github_release::install <repo> <asset_regex> <inner_path_glob> <target_name>
# Скачивает последний релиз с GitHub, ищет ассет по regex, распаковывает
# и кладёт найденный бинарник в /usr/local/bin/<target_name>. Идемпотентно
# — пропускает, если <target_name> уже есть в PATH.
#
# inner_path_glob сравнивается с полным путём внутри архива (`find
# -path "*<glob>"`), а не только с именем файла — некоторые архивы
# (например fastfetch) содержат несколько файлов с одинаковым базовым
# именем (бинарник и shell-completion), поэтому чистого `-name`
# недостаточно; для точного совпадения передавать что-то вроде
# "usr/bin/tool", а не просто "tool". Если ассет — не .tar.gz, а голый
# бинарник (например jq публикует именно так), inner_path_glob
# игнорируется — можно передать пустую строку.
github_release::install() {
  local repo="$1" asset_regex="$2" inner_path_glob="$3" target_name="$4"

  if command -v "$target_name" >/dev/null 2>&1; then
    echo "github-release: $target_name уже установлен, пропускаю"
    return 0
  fi

  local url
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
    | cut -d'"' -f4 \
    | grep -E "$asset_regex" | head -n1)"

  if [ -z "$url" ]; then
    echo "github-release: не удалось найти релиз для $target_name (repo=$repo, pattern=$asset_regex)" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp -d)"
  echo "github-release: скачиваю $target_name: $url"

  local bin_path
  if [[ "$url" == *.tar.gz ]]; then
    curl -fsSL "$url" -o "$tmp/asset.tar.gz"
    tar -xzf "$tmp/asset.tar.gz" -C "$tmp"
    bin_path="$(find "$tmp" -type f -path "*$inner_path_glob" | head -n1)"
  else
    curl -fsSL "$url" -o "$tmp/$target_name"
    bin_path="$tmp/$target_name"
  fi

  if [ -z "$bin_path" ] || [ ! -f "$bin_path" ]; then
    echo "github-release: бинарник '$inner_path_glob' не найден в архиве $target_name" >&2
    rm -rf "$tmp"
    return 1
  fi

  sudo install -m 0755 "$bin_path" "/usr/local/bin/$target_name"
  rm -rf "$tmp"
  echo "github-release: $target_name установлен в /usr/local/bin/$target_name"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "scripts/lib/github-release.sh: подключать через source, не запускать напрямую" >&2
  exit 1
fi
