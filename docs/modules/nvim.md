# modules/nvim.sh

Конфиг Neovim: `~/.config/nvim/init.lua` из `config/nvim/init.lua` (та же
схема бэкапа через `cmp`, что и у zsh/tmux) + lazy.nvim (менеджер
плагинов, bootstrap в самом init.lua через `git clone`) + базовый набор
плагинов: nvim-tree (дерево файлов, `<leader>e`), lualine (статус-бар),
telescope+plenary (нечёткий поиск, `<leader>ff/fg/fb`), nvim-treesitter
(подсветка на основе AST), tokyonight (цветовая схема), gitsigns
(git-знаки на полях), Comment.nvim (комментирование `gcc`/`gc`),
which-key (подсказки по `<leader>`-комбинациям), indent-blankline
(направляющие линии отступов). LSP и автодополнение сознательно не
включены — отдельный, более тяжёлый шаг (nvim-lspconfig + mason), не
входит в текущий базовый уровень.

## Бинарник ставится с GitHub Releases, а не из пакетного менеджера

(`nvim::install_package` в модуле, не `os::pkg_install`) — решение
пользователя. Причина: neovim в репозиториях Ubuntu/Debian сильно
устаревший (0.9.5), там ещё нет `vim.uv` (появился в 0.10), от которого
зависит bootstrap lazy.nvim. По той же причине это не
`github_release::install` из `scripts/lib/github-release.sh` (тот
рассчитан на самодостаточный статический бинарник вроде eza/delta/curlie)
— релизный архив neovim это дерево `bin/+lib/+share/` (бинарнику в
рантайме нужны файлы из `share/nvim/runtime`), распаковывается целиком
поверх `/usr/local`. Т.к. свежий neovim теперь ставит этот модуль,
`neovim` убран из пакетного списка `modules/base.sh` (дублирования не
делаем, тот же принцип, что и с `git-delta`/`gh` в других модулях).

## Настройки, перенесённые из личного `~/.vimrc` (WSL Ubuntu)

Пользователь много лет использовал обычный vim с ручным `.vimrc`
(без плагин-менеджера). При портировании его настроек в `init.lua`
(2026-08-25) часть решений явно уточнена, а не унаследована автоматически:

- `relativenumber` **выключен** — в личном `.vimrc` было явное
  `norelativenumber`, пользователь подтвердил, что предпочитает
  абсолютную нумерацию строк.
- `cursorline` и `history=1000` перенесены как есть.
- Гашение подсветки поиска (`nohlsearch`) теперь висит на **двух**
  маппингах: `<leader>h` (уже был в knrc) и `<Esc>` (из личного
  `.vimrc`) — оставлены оба по решению пользователя, не заменяли один
  другим.
- `<C-s>` (save) в normal и insert mode добавлен по образцу личного
  `.vimrc`.
- Не перенесены: `showcmd`/`showmode`/`wildmenu` (в neovim и так
  включены по умолчанию, дублирование лишнее) и мануальные
  `<C-c>`/`<C-v>` маппинги на copy/paste в системный буфер — избыточны,
  т.к. `clipboard=unnamedplus` уже синхронизирует безымянный регистр с
  системным буфером напрямую.

## Реальные баги, пойманные при тестировании

- `nvim::install_plugins` ставит `gcc` перед `Lazy! sync` — nvim-treesitter
  компилирует парсеры через `:TSUpdate`, без C-компилятора сборка падает
  с "No C compiler found".
- nvim-treesitter в конфиге закреплён на `branch = 'master'` (не `main`)
  — `main` это переписанный в 2025 новый мажор без
  `require('nvim-treesitter.configs').setup()`, с другим API; `master` —
  поддерживаемая legacy-ветка со старым простым API, которым и
  пользуется конфиг.

Требует `scripts/lib/os-detect.sh` (`os::pkg_install` для
`diffutils`/`gcc`).

**Тестирование**: end-to-end в контейнере Ubuntu 24.04: установка с нуля
(включая скачивание бинарника и headless-синхронизацию всех плагинов без
ошибок), идемпотентность (повторный запуск), бэкап конфига при локальном
отличии, и полный прогон через `install.sh` (`DOTFILES_MODULES=nvim`).

gitsigns/Comment.nvim/which-key/indent-blankline добавлены позже и пока
не прогонялись через контейнерный test-module (Docker Desktop был
недоступен в момент добавления) — при следующем изменении модуля nvim
прогнать `scripts/test-module.sh nvim ubuntu24` заново.

2026-08-25: после переноса настроек из личного `~/.vimrc` (см. раздел
выше) повторно прогнан `scripts/test-module.sh base,nvim ubuntu24` —
два запуска подряд в одном контейнере, оба чистые (headless-синхронизация
плагинов без ошибок, идемпотентность подтверждена). Тестировали именно
`base,nvim`, а не голый `nvim` — модуль nvim не ставит `curl` сам, тот
идёт из `base`.
