--[[
  Based on kickstart.nvim by TJ DeVries
  Customized for: Neon (custom), Copilot, auto-save, TypeScript/Python/Ruby
  Fork of https://github.com/nvim-lua/kickstart.nvim
--]]

-- Set leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ── Options ─────────────────────────────────────────────────────────
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = 'a'
vim.opt.showmode = false
vim.opt.clipboard = 'unnamedplus'
vim.opt.breakindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
vim.opt.inccommand = 'split'
vim.opt.cursorline = true
vim.opt.scrolloff = 10
vim.opt.hlsearch = true
vim.opt.termguicolors = true

-- ── Keymaps ─────────────────────────────────────────────────────────
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Split navigation
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus left' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus right' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus down' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus up' })

-- Ctrl+Click go to definition
vim.keymap.set('n', '<C-LeftMouse>', '<LeftMouse><cmd>lua vim.lsp.buf.definition()<CR>')

-- ── Autocommands ────────────────────────────────────────────────────
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function() vim.hl.on_yank() end,
})

-- ── Plugin Manager (lazy.nvim) ──────────────────────────────────────
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
end
vim.opt.rtp:prepend(lazypath)

-- ── Plugins ─────────────────────────────────────────────────────────
require('lazy').setup({

  -- Detect tabstop and shiftwidth automatically
  'tpope/vim-sleuth',

  -- ── Which Key ───────────────────────────────────────────────────
  {
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      spec = {
        { '<leader>c', group = '[C]ode', mode = { 'n', 'x' } },
        { '<leader>d', group = '[D]ocument' },
        { '<leader>r', group = '[R]ename' },
        { '<leader>s', group = '[S]earch' },
        { '<leader>w', group = '[W]orkspace' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>a', group = '[A]I', mode = { 'n', 'v' } },
        { '<leader>b', group = '[B]uffer' },
        { '<leader>g', group = '[G]it' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
        { '<leader>x', group = 'Trouble' },
      },
    },
  },

  -- ── Telescope ───────────────────────────────────────────────────
  {
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function() return vim.fn.executable 'make' == 1 end,
      },
      'nvim-telescope/telescope-ui-select.nvim',
    },
    config = function()
      require('telescope').setup {
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
        },
      }
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  -- ── LSP ─────────────────────────────────────────────────────────
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'williamboman/mason.nvim', opts = {} },
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      { 'j-hui/fidget.nvim', opts = {} },
      { 'folke/lazydev.nvim', ft = 'lua', opts = {
        library = {
          { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
        },
      }},
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end
          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- Highlight references on cursor hold
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })
            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- Inlay hints toggle
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- LSP capabilities (enhanced by blink.cmp)
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- ── Language Servers ──────────────────────────────────────────
      local servers = {
        ts_ls = {},
        pyright = {},
        ruby_lsp = {},
        lua_ls = {
          settings = {
            Lua = {
              completion = { callSnippet = 'Replace' },
              diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

      local ensure_installed = vim.tbl_keys(servers)
      vim.list_extend(ensure_installed, {
        'stylua',
        'prettierd',
      })

      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        ensure_installed = {},
        automatic_installation = false,
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },

  -- ── Conform (format on save) ────────────────────────────────────
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function() require('conform').format { async = true, lsp_fallback = true } end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        local disable_filetypes = { c = true, cpp = true }
        if disable_filetypes[vim.bo[bufnr].filetype] then return end
        return { timeout_ms = 2500, lsp_fallback = true }
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        javascript = { 'prettierd', 'prettier', stop_after_first = true },
        typescript = { 'prettierd', 'prettier', stop_after_first = true },
        javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        json = { 'prettierd', 'prettier', stop_after_first = true },
        html = { 'prettierd', 'prettier', stop_after_first = true },
        css = { 'prettierd', 'prettier', stop_after_first = true },
        markdown = { 'prettierd', 'prettier', stop_after_first = true },
        yaml = { 'prettierd', 'prettier', stop_after_first = true },
        python = { 'black' },
        ruby = { 'rubocop' },
      },
    },
  },

  -- ── Completion (blink.cmp) ──────────────────────────────────────
  {
    'saghen/blink.cmp',
    dependencies = {
      'rafamadriz/friendly-snippets',
    },
    version = '1.*',
    opts = {
      keymap = { preset = 'default' },
      appearance = {
        nerd_font_variant = 'mono',
      },
      completion = {
        documentation = { auto_show = true },
      },
      sources = {
        default = { 'lazydev', 'path' },
        providers = {
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            score_offset = 100,
          },
        },
      },
      signature = { enabled = true },
    },
  },

  -- ── GitHub Copilot ──────────────────────────────────────────────
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = '<C-a>',
          next = '<C-]>',
          prev = '<C-[>',
          dismiss = '<C-\\>',
        },
      },
      panel = { enabled = false },
    },
  },

  -- ── CopilotChat ───────────────────────────────────────────────
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    dependencies = { 'zbirenbaum/copilot.lua', 'nvim-lua/plenary.nvim' },
    cmd = { 'CopilotChat', 'CopilotChatExplain', 'CopilotChatReview', 'CopilotChatFix', 'CopilotChatTests' },
    keys = {
      { '<leader>ac', '<cmd>CopilotChat<CR>', desc = '[A]I [C]hat' },
      { '<leader>ae', '<cmd>CopilotChatExplain<CR>', mode = { 'n', 'v' }, desc = '[A]I [E]xplain' },
      { '<leader>ar', '<cmd>CopilotChatReview<CR>', mode = { 'n', 'v' }, desc = '[A]I [R]eview' },
      { '<leader>af', '<cmd>CopilotChatFix<CR>', mode = { 'n', 'v' }, desc = '[A]I [F]ix' },
      { '<leader>at', '<cmd>CopilotChatTests<CR>', mode = { 'n', 'v' }, desc = '[A]I [T]ests' },
    },
    opts = {},
  },

  -- ── Auto-save ───────────────────────────────────────────────────
  {
    'okuuva/auto-save.nvim',
    event = { 'InsertLeave', 'TextChanged' },
    opts = {
      execution_message = { enabled = false },
      trigger_events = {
        immediate_save = { 'BufLeave', 'FocusLost' },
        defer_save = { 'InsertLeave', 'TextChanged' },
      },
      debounce_delay = 1000,
    },
  },

  -- ── Treesitter ──────────────────────────────────────────────────
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    build = ':TSUpdate',
    lazy = false,
    config = function()
      require('nvim-treesitter').install({
        'bash', 'c', 'css', 'diff', 'html', 'javascript', 'json',
        'lua', 'luadoc', 'markdown', 'markdown_inline', 'nix',
        'python', 'query', 'ruby', 'rust', 'toml', 'tsx',
        'typescript', 'vim', 'vimdoc', 'yaml',
      })

      vim.api.nvim_create_autocmd('FileType', {
        callback = function()
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },

  -- ── Treesitter Text Objects ─────────────────────────────────────
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('nvim-treesitter-textobjects').setup {
        select = {
          enable = true,
          lookahead = true,
          keymaps = {
            ['af'] = '@function.outer',
            ['if'] = '@function.inner',
            ['ac'] = '@class.outer',
            ['ic'] = '@class.inner',
            ['aa'] = '@parameter.outer',
            ['ia'] = '@parameter.inner',
          },
        },
        move = {
          enable = true,
          set_jumps = true,
          goto_next_start = {
            [']m'] = '@function.outer',
            [']]'] = '@class.outer',
          },
          goto_previous_start = {
            ['[m'] = '@function.outer',
            ['[['] = '@class.outer',
          },
        },
      }
    end,
  },

  -- ── Surround ────────────────────────────────────────────────────
  {
    'kylechui/nvim-surround',
    version = '*',
    event = 'VeryLazy',
    opts = {},
  },

  -- ── Autopairs ───────────────────────────────────────────────────
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    opts = {},
  },

  -- ── Neo-tree (file explorer) ─────────────────────────────────────
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'echasnovski/mini.nvim',
      'MunifTanjim/nui.nvim',
    },
    keys = {
      { '<C-n>', '<cmd>Neotree toggle<CR>', desc = 'Toggle file tree' },
    },
    opts = {
      filesystem = {
        follow_current_file = { enabled = true },
        filtered_items = { visible = true },
      },
      window = { width = 30 },
    },
  },

  -- ── Gitsigns ────────────────────────────────────────────────────
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '│' },
        change = { text = '│' },
        delete = { text = '󰍵' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      word_diff = true,
      on_attach = function(bufnr)
        local gs = require('gitsigns')
        local map = function(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end
        map('n', ']h', gs.next_hunk, 'Next hunk')
        map('n', '[h', gs.prev_hunk, 'Previous hunk')
        map('n', '<leader>hs', gs.stage_hunk, 'Stage hunk')
        map('n', '<leader>hr', gs.reset_hunk, 'Revert hunk')
        map('n', '<leader>hu', gs.undo_stage_hunk, 'Undo stage hunk')
        map('n', '<leader>hp', gs.preview_hunk, 'Preview hunk')
        map('n', '<leader>hS', gs.stage_buffer, 'Stage buffer')
        map('n', '<leader>hR', gs.reset_buffer, 'Revert buffer')
        map('n', '<leader>hb', gs.blame_line, 'Blame line')
      end,
    },
  },

  -- ── Diffview (side-by-side diffs) ─────────────────────────────────
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<leader>gd', '<cmd>DiffviewOpen<CR>', desc = '[G]it [D]iff view' },
      { '<leader>gh', '<cmd>DiffviewFileHistory %<CR>', desc = '[G]it file [H]istory' },
      { '<leader>gH', '<cmd>DiffviewFileHistory<CR>', desc = '[G]it repo [H]istory' },
    },
    opts = {},
  },

  -- ── Fugitive (git commands) ──────────────────────────────────────
  {
    'tpope/vim-fugitive',
    cmd = { 'Git', 'Gdiffsplit', 'Gvdiffsplit' },
    keys = {
      { '<leader>gf', '<cmd>Gvdiffsplit<CR>', desc = '[G]it di[F]f split' },
      { '<leader>gb', '<cmd>Git blame<CR>', desc = '[G]it [B]lame' },
    },
  },

  -- ── Bufferline (buffer tabs) ──────────────────────────────────
  {
    'akinsho/bufferline.nvim',
    version = '*',
    event = 'VeryLazy',
    dependencies = { 'echasnovski/mini.nvim' },
    keys = {
      { '<S-h>', '<cmd>BufferLineCyclePrev<CR>', desc = 'Prev buffer' },
      { '<S-l>', '<cmd>BufferLineCycleNext<CR>', desc = 'Next buffer' },
      { '<leader>bp', '<cmd>BufferLineTogglePin<CR>', desc = '[B]uffer [P]in' },
      { '<leader>bx', '<cmd>BufferLineCloseOthers<CR>', desc = '[B]uffer close others' },
    },
    opts = {
      options = {
        diagnostics = 'nvim_lsp',
        always_show_bufferline = false,
        offsets = {
          { filetype = 'neo-tree', text = 'File Explorer', highlight = 'Directory' },
        },
      },
    },
  },

  -- ── Noice (modern command/message UI) ─────────────────────────
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = { 'MunifTanjim/nui.nvim' },
    opts = {
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
      },
      presets = {
        bottom_search = true,
        command_popup = true,
        long_message_to_split = true,
        lsp_doc_border = true,
      },
    },
  },

  -- ── Flash (jump anywhere) ─────────────────────────────────────
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    keys = {
      { 's', mode = { 'n', 'x', 'o' }, function() require('flash').jump() end, desc = 'Flash jump' },
      { 'S', mode = { 'n', 'x', 'o' }, function() require('flash').treesitter() end, desc = 'Flash treesitter' },
    },
    opts = {},
  },

  -- ── Harpoon (quick file marks) ────────────────────────────────
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<leader>ha', function() require('harpoon'):list():add() end, desc = '[H]arpoon [A]dd' },
      { '<C-e>', function() require('harpoon').ui:toggle_quick_menu(require('harpoon'):list()) end, desc = 'Harpoon menu' },
      { '<C-1>', function() require('harpoon'):list():select(1) end, desc = 'Harpoon file 1' },
      { '<C-2>', function() require('harpoon'):list():select(2) end, desc = 'Harpoon file 2' },
      { '<C-3>', function() require('harpoon'):list():select(3) end, desc = 'Harpoon file 3' },
      { '<C-4>', function() require('harpoon'):list():select(4) end, desc = 'Harpoon file 4' },
    },
    opts = {},
  },

  -- ── Neoscroll (smooth scrolling) ──────────────────────────────
  {
    'karb94/neoscroll.nvim',
    event = 'VeryLazy',
    opts = { duration_multiplier = 0.6 },
  },

  -- ── Trouble (diagnostics panel) ───────────────────────────────
  {
    'folke/trouble.nvim',
    cmd = 'Trouble',
    keys = {
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<CR>', desc = 'Diagnostics (Trouble)' },
      { '<leader>xd', '<cmd>Trouble diagnostics toggle filter.buf=0<CR>', desc = 'Buffer diagnostics' },
      { '<leader>xs', '<cmd>Trouble symbols toggle focus=false<CR>', desc = 'Symbols (Trouble)' },
      { ']t', function() require('trouble').next({ skip_groups = true, jump = true }) end, desc = 'Next trouble' },
      { '[t', function() require('trouble').prev({ skip_groups = true, jump = true }) end, desc = 'Prev trouble' },
    },
    opts = {},
  },

  -- ── Persistence (session management) ──────────────────────────
  {
    'folke/persistence.nvim',
    event = 'BufReadPre',
    keys = {
      { '<leader>qs', function() require('persistence').load() end, desc = 'Restore session' },
      { '<leader>ql', function() require('persistence').load({ last = true }) end, desc = 'Restore last session' },
      { '<leader>qd', function() require('persistence').stop() end, desc = "Don't save session" },
    },
    opts = {},
  },

  -- ── Undotree (visual undo history) ────────────────────────────
  {
    'mbbill/undotree',
    keys = {
      { '<leader>u', vim.cmd.UndotreeToggle, desc = '[U]ndo tree' },
    },
  },

  -- ── Todo Comments ───────────────────────────────────────────────
  {
    'folke/todo-comments.nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = false },
  },

  -- ── Mini (statusline + icons) ───────────────────────────────────
  {
    'echasnovski/mini.nvim',
    config = function()
      require('mini.statusline').setup { use_icons = true }
      require('mini.icons').setup()
    end,
  },

  -- ── Fidget (LSP progress) ──────────────────────────────────────
  -- Already loaded as LSP dependency above

}, {
  ui = {
    icons = {},
  },
})

-- ── Colorscheme ───────────────────────────────────────────────────
-- Custom neon theme lives in colors/neon.lua
vim.cmd.colorscheme 'neon'

-- ── Fugitive diff resize ──────────────────────────────────────────
-- Resize fugitive diff split to 40% of remaining space (after neo-tree)
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('fugitive-resize', { clear = true }),
  pattern = 'fugitive://*',
  callback = function()
    local remaining = vim.o.columns - 30
    vim.cmd('vertical resize ' .. math.floor(remaining * 0.4))
  end,
})
