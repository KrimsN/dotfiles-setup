# modules/python-tools.sh

Ставит `uv` (менеджер пакетов и версий Python, написан на Rust) через
официальный скрипт `astral.sh/uv/install.sh`, затем `ruff`
(линтер/форматтер на Rust) и `ty` (type checker на Rust, тоже от
astral) через `uv tool install ruff` / `uv tool install ty`.

## Миграция на диспетчер (2026-08-25)

`python_tools::install` теперь вызывает `pkg::install uv` (метод
`curl-sh`) и `pkg::install ruff` (метод `custom`) — см.
[scripts/lib/pkg-registry.sh](../../scripts/lib/pkg-registry.sh) и
[docs/design/pkg-metadata-json.md](../design/pkg-metadata-json.md).
Технические детали (URL инсталлера, переменные окружения) — в
[data/packages/methods/curl-sh.json](../../data/packages/methods/curl-sh.json).

`python_tools::install_ruff` **осталась в этом файле как есть** —
диспетчер не умеет ставить ruff декларативно (это обёртка над уже
установленным `uv`, не самостоятельный источник), поэтому
`registry.json` ссылается на неё по имени как на `custom`-обработчик
(`"handler": "python_tools::install_ruff"`). Идемпотентность и порядок
вызова (после `localbin::ensure_path`, чтобы `uv` уже был в PATH
текущего процесса) не изменились.

## Добавление ty (2026-09-04)

`ty` (type checker astral-sh, тоже на Rust) добавлен по тому же
паттерну, что ruff: `python_tools::install_ty` в `python-tools.sh`,
запись в `registry.json` с `"type": "custom", "handler":
"python_tools::install_ty", "requires": ["uv"]`, вызов `pkg::install
ty` в `python_tools::install` — после `ruff`, тоже уже после
`localbin::ensure_path`. Без github-fallback (в отличие от ruff) —
не проверялось, есть ли у ty публикуемые статические бинарники по
такой же схеме, как у ruff.

## Решения пользователя

- **uv** ставится официальным `curl | sh`-скриптом, а не через
  `github_release::install` (как остальные Rust-бинарники в
  `cli-tools.sh`) — это способ доставки, который рекомендует сам проект
  uv, включает поддержку `uv self update`.
- **Toolchain Rust (rustup/cargo/rustc) не ставится** — uv и ruff это
  готовые бинарники, компилировать их на месте не нужно.
- **Дополнительно к uv — только ruff.** uv сам умеет ставить версии
  Python (`uv python install`) и заменяет venv/pip/pipx/poetry в
  большинстве сценариев, поэтому отдельные pyenv/pipx/poetry не
  ставятся.

## PATH

`uv` и `uv tool install` кладут бинарники в `~/.local/bin`. Официальному
инсталлеру правка shell rc-файлов отключена (`INSTALLER_NO_MODIFY_PATH=1`,
см. `data/packages/methods/curl-sh.json`) — иначе он допишет `~/.zshrc`,
который `zsh.sh` перезаписывает целиком из шаблона при каждом прогоне, и
правка не переживёт повторную установку. Вместо этого PATH управляется
тем же паттерном, что `aliases.sh`/`tmux.sh`: снипет
`~/.config/knrc/path.sh`, подключаемый условной строкой из `config/zshrc`
и управляемым блоком в `~/.bashrc` через `rcfile::upsert_block`.

Сам снипет пишет не этот модуль, а `localbin::ensure_path`
(`scripts/lib/localbin.sh`, см. [localbin.md](localbin.md)): в тот же
`~/.local/bin` `install.sh` ставит лаунчер `knrc`, и каталог нужен в
PATH независимо от того, выбран ли модуль python-tools. Порядок вызова
внутри `python_tools::install` не изменился — между `uv` и `ruff`.

## Тестирование

**До миграции** (актуально для установки uv — сама логика идемпотентности
теперь в `pkg_registry::_run_curl_sh`, тот же принцип, что описан ниже,
перенесён туда без изменений): `base,python-tools` на Ubuntu 24.04 через
`.claude/skills/test-module/` (два прогона в одном контейнере). Второй
прогон подтверждает идемпотентность (`uv`/`ruff` не переустанавливаются
повторно — при первой реализации был баг: проверка `command -v uv`
ничего не находила на втором прогоне, потому что PATH обновляется
только внутри самого текущего запуска `install.sh`, а не между
отдельными его вызовами; исправлено дополнительной проверкой файла
`$PYTHON_TOOLS_BIN_DIR/uv`/`ruff` напрямую — этот же способ проверки
теперь в `data/packages/methods/curl-sh.json`: `check.command` +
`check.path`). Также проверена работа `uv`/`ruff` из интерактивного
`bash`-шелла после установки (через `~/.bashrc`).

**После миграции:** проверено юнит-тестами диспетчера (включая
рекурсивный `requires: [uv]` для ruff через реальный `curl-sh`-путь),
интеграционным тестом на заглушках, и end-to-end через
`.claude/skills/test-module/` на Ubuntu 24.04, Debian 12, Fedora, CentOS
Stream 9 (в связке `base,cli-tools,extras,python-tools`, два прогона на
идемпотентность) — везде `uv`/`ruff` ставятся на первом прогоне и
корректно распознаются как уже установленные на втором.

**После добавления ty (2026-09-04):** `base,python-tools` на Ubuntu
24.04 через `.claude/skills/test-module/` (два прогона в одном
контейнере). `ty` ставится на первом прогоне (`uv tool install ty`) и
корректно распознаётся как уже установленный на втором
(`command -v ty` через файл `$PYTHON_TOOLS_BIN_DIR/ty`), как и
ruff/uv. Другие дистрибутивы отдельно не гонялись — изменение не
затрагивает ветвление по `OS_FAMILY`, логика идентична уже
протестированной для ruff.
