# modules/nvim.sh

Конфиг Neovim: `~/.config/nvim/init.lua` из `config/nvim/init.lua` (та же
схема бэкапа через `cmp`, что и у zsh/tmux) + lazy.nvim (менеджер
плагинов, bootstrap в самом init.lua через `git clone`) + базовый набор
плагинов: nvim-tree (дерево файлов, `<leader>e`), lualine (статус-бар),
telescope+plenary (нечёткий поиск, `<leader>ff/fg/fb`), nvim-treesitter
(подсветка на основе AST), tokyonight (цветовая схема). LSP и
автодополнение сознательно не включены — отдельный, более тяжёлый шаг
(nvim-lspconfig + mason), не входит в текущий базовый уровень.

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
