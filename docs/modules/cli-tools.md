# modules/cli-tools.sh

Ставит все 10 CLI-инструментов нового поколения (ripgrep, fd, fzf, bat,
jq, httpie, eza, delta, curlie, zoxide).

## Миграция на диспетчер (2026-08-25)

Модуль переведён с собственных bash-функций (`cli::install_pkg_group`,
`cli::fallback_*`, `cli::install_eza`/`delta`/`curlie`/`zoxide`) на общий
диспетчер `pkg::install` — см. [scripts/lib/pkg-registry.sh](../../scripts/lib/pkg-registry.sh)
и [docs/design/pkg-metadata-json.md](../design/pkg-metadata-json.md).
Способ установки каждого пакета, порядок приоритета (пакетный менеджер
vs GitHub Releases vs pip) и обоснование выбора — теперь декларативно в
[data/packages/registry.json](../../data/packages/registry.json), не в
этом файле. `cli::install` сводится к циклу `pkg::install "$pkg"` по
списку `CLI_PACKAGES` плюс то, что диспетчер не моделирует:

- **Симлинки** `fd`/`bat` → `fdfind`/`batcat` (переименование бинарника
  внутри пакета на apt/Debian-семействе, конфликт имён с другими
  пакетами) — `cli::ensure_symlinks`, без изменений от старой реализации.
- **Конфиг bat** (`config/bat.conf` → `~/.config/bat/config`) —
  `cli::write_bat_config`, без изменений.

При миграции нашёлся реальный пробел: в старом коде `epel::ensure`
вызывался один раз перед всей группой пакетов (ripgrep, fd, fzf, bat,
jq, httpie), но в `registry.json` изначально `prereq: epel::ensure` был
только у `httpie`/`tldr`. Добавлен и для ripgrep/fd/fzf/bat — иначе их
`pkg`-метод падал бы на CentOS/RHEL без EPEL.

Требует `scripts/lib/os-detect.sh` и `scripts/lib/pkg-registry.sh` (вместо
`epel.sh`/`github-release.sh` напрямую — их теперь вызывает диспетчер).

## Тестирование

**До миграции (актуально для старой реализации, полностью замененной
19-строчным циклом по `pkg::install` — сама логика pkg/GitHub/pip
fallback теперь генерическая и живёт в `scripts/lib/pkg-registry.sh`,
описанные ниже прогоны её не покрывают напрямую):**

end-to-end (установка + двойной запуск на идемпотентность) в Ubuntu
24.04, Fedora 39, CentOS Stream 9 (включая EPEL+CRB) — на всех три
версии совпали ассеты, скачанные с GitHub. Дополнительно проверена
установка (без повторного прогона) на Debian 12. Конфиг bat
дополнительно перепроверен через `scripts/test-module.sh base,cli-tools`
на Ubuntu 24.04 и Fedora (latest, dnf5) — записывается идемпотентно на
обоих прогонах. Fallback-путь проверен на Ubuntu 24.04: `ripgrep`
заблокирован через `/etc/apt/preferences.d` (имитация отсутствия пакета
в корпоративном репозитории), установка переключилась на GitHub Releases,
остальные пять пакетов встали штатно через apt без прерывания.

**После миграции:** диспетчер и переписанный `cli::install` проверены
юнит-тестами на заглушках и интеграционным тестом на заглушках, а затем
end-to-end через `.claude/skills/test-module/` (`base,cli-tools,extras,
python-tools`, два прогона в одном контейнере на идемпотентность) на всех
четырёх целевых дистрибутивах: Ubuntu 24.04, Debian 12, Fedora, CentOS
Stream 9 — везде чисто, без единой ошибки на обоих прогонах. CentOS 9
отдельно подтвердил фикс, найденный при миграции: ripgrep, fd, fzf, bat
(и httpie) реально ставятся из EPEL, `epel::ensure` как `prereq`
срабатывает перед каждым из них.
