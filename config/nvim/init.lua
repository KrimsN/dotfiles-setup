-- Managed by dotfiles-setup.
-- Копируется в ~/.config/nvim/init.lua модулем modules/nvim.sh. При
-- отличии от уже существующего файла делается бэкап (см. nvim::write_config).

-- === Базовые настройки ===
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.mouse = 'a'
-- Системный буфер обмена по умолчанию, а не безымянный регистр vim —
-- иначе yank/paste не синхронизируются с буфером ОС/tmux
opt.clipboard = 'unnamedplus'
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
-- Подсветку последнего поиска гасим маппингом ниже, а не отключаем hlsearch
opt.hlsearch = true
opt.splitright = true
opt.splitbelow = true
opt.termguicolors = true
-- Постоянный undo-файл — история отмен переживает закрытие файла
opt.undofile = true
opt.scrolloff = 8
-- Столбец под знаки git/диагностики всегда виден, чтобы текст не "прыгал"
opt.signcolumn = 'yes'
opt.updatetime = 250

-- === Базовые keymaps ===
local map = vim.keymap.set
map('n', '<leader>h', ':nohlsearch<CR>', { desc = 'Убрать подсветку поиска' })
map('n', '<C-h>', '<C-w>h', { desc = 'Перейти в панель слева' })
map('n', '<C-j>', '<C-w>j', { desc = 'Перейти в панель снизу' })
map('n', '<C-k>', '<C-w>k', { desc = 'Перейти в панель сверху' })
map('n', '<C-l>', '<C-w>l', { desc = 'Перейти в панель справа' })

-- === lazy.nvim: bootstrap менеджера плагинов ===
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
-- modules/nvim.sh ставит nvim с GitHub Releases (>= 0.10), vim.uv гарантированно есть
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- === Плагины ===
require('lazy').setup({
  -- Цветовая схема
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme('tokyonight-night')
    end,
  },

  -- Дерево файлов
  {
    'nvim-tree/nvim-tree.lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('nvim-tree').setup({})
      map('n', '<leader>e', ':NvimTreeToggle<CR>', { desc = 'Дерево файлов' })
    end,
  },

  -- Статус-бар
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('lualine').setup({})
    end,
  },

  -- Нечёткий поиск по файлам/содержимому
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local builtin = require('telescope.builtin')
      map('n', '<leader>ff', builtin.find_files, { desc = 'Найти файл' })
      map('n', '<leader>fg', builtin.live_grep, { desc = 'Поиск по содержимому' })
      map('n', '<leader>fb', builtin.buffers, { desc = 'Список буферов' })
    end,
  },

  -- Подсветка синтаксиса на основе AST.
  -- branch = 'master' — намеренно: ветка main это переписанный в 2025
  -- новый мажор без require('nvim-treesitter.configs').setup(), с
  -- совсем другим API (vim.treesitter.start() и т.д.); master —
  -- поддерживаемая legacy-ветка со старым, простым и хорошо
  -- задокументированным API, его и используем для базового конфига.
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = { 'bash', 'lua', 'python', 'markdown', 'json', 'yaml' },
        highlight = { enable = true },
      })
    end,
  },

  -- Знаки изменений git на полях (+/~/-) и переход между хунками
  {
    'lewis6991/gitsigns.nvim',
    config = function()
      require('gitsigns').setup({})
    end,
  },

  -- Закомментировать строку/блок с учётом синтаксиса файла: gcc, gc
  {
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup({})
    end,
  },

  -- Подсказка доступных сочетаний клавиш при наборе <leader>
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    config = function()
      require('which-key').setup({})
    end,
  },

  -- Визуальные направляющие отступов
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    config = function()
      require('ibl').setup({})
    end,
  },
})
