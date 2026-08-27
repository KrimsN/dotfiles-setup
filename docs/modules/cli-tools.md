# modules/cli-tools.sh

Ставит все 11 CLI-инструментов нового поколения (ripgrep, fd, fzf, bat,
jq, httpie, eza, delta, curlie, zoxide, direnv).

## direnv (2026-08-25)

Автоактивация `.venv` (создаётся через уже установленный `uv`) и прочих
project-scoped переменных окружения при `cd` в каталог с `.envrc` —
согласовано пользователем, добавлено к остальным CLI-инструментам, не в
`python-tools.sh`: сама установка direnv не специфична для Python
(`data/packages/registry.json` трактует его как обычный CLI-инструмент
через `pkg::install`), только сценарий использования завязан на uv.

Метод `pkg`: есть штатно в apt (Debian/Ubuntu) и dnf (Fedora). На
yum-семействе (CentOS/RHEL) пакета нет ни в базовых репах, ни в EPEL —
проверено: `src.fedoraproject.org/rpms/direnv` не собирает
epel8/epel9-таргеты, только текущие релизы Fedora. `methods/pkg.json`
оставляет `"yum": ""` — диспетчер видит пустое имя пакета, метод `pkg`
проваливается для `yum`, и `pkg::install` уходит на `github`-метод
(приоритет 2), как для CentOS/RHEL в целом.

Метод `github`: проект публикует голые бинарники
`direnv.linux-amd64`/`direnv.linux-arm64` (не `.tar.gz`) — как `jq`,
`inner_path_glob` не используется. `{arch_go}` совпадает с именованием
архитектуры в ассетах напрямую, `asset_by_arch` не понадобился.

Хук шелла — `eval "$(direnv hook zsh)"` в `config/zshrc`, под guard
`command -v direnv`, сразу после хука zoxide (тот же паттерн: fzf/zoxide/
direnv все находятся ПОСЛЕ `source "$ZSH/oh-my-zsh.sh"`, т.к. это
требование самого direnv — хук должен переопределять `cd`/`chpwd` после
того, как всё остальное шелл-окружение уже settled).

Проверено через `.claude/skills/test-module/` (`base,cli-tools`, два
прогона на идемпотентность в одном контейнере): Ubuntu 24.04 —
`direnv` ставится через apt (`pkg`-метод), CentOS Stream 9 — apt-пакета
нет («No match for argument: direnv»), диспетчер уходит на `github`
(`direnv.linux-amd64` с GitHub Releases). На обоих дистрибутивах второй
прогон распознаёт уже установленный `direnv` и не переустанавливает
его.

## direnvrc / layout_uv (2026-08-27)

Помимо самого хука в шелле, `cli::write_direnvrc` кладёт
[config/direnvrc](../../config/direnvrc) в `~/.config/direnv/direnvrc`
(та же схема, что и `cli::write_bat_config`: `backup::create_if_diff`
перед перезаписью, `DRY_RUN` guard). Файл определяет `layout_uv` —
функцию для direnv-стандарта `layout`, аналогичную встроенным `layout
python`/`layout ruby`: создаёт `.venv` через уже установленный `uv`,
если его ещё нет, и добавляет `.venv/bin` в `PATH` на время нахождения
в каталоге.

Без этого файла пользователю пришлось бы в каждом проекте вручную
писать в `.envrc` активацию venv с проверками существования каталога.
С `layout_uv` в `.envrc` проекта достаточно одной строки:

```
layout uv
```

`direnv allow` в конкретном проекте по-прежнему нужен один раз (это
осознанный барьер direnv против исполнения произвольного кода из
`.envrc` при простом `cd` в чужой репозиторий) — модуль не создаёт и не
разрешает `.envrc` за пользователя, только даёт общий хелпер, доступный
во всех проектах сразу после установки.

Откат: `uninstall::plan_cli_tools` восстанавливает/удаляет
`~/.config/direnv/direnvrc` по той же схеме, что и `~/.config/bat/config`.

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
