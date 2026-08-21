return {
  {
    -- Successor to nvim-ts-rainbow2; uses nvim's native treesitter API directly
    "HiPhish/rainbow-delimiters.nvim",
    init = function()
      vim.g.rainbow_delimiters = {
        strategy = {
          [""] = "rainbow-delimiters.strategy.global",
        },
        query = {
          [""] = "rainbow-delimiters",
          lua = "rainbow-blocks",
        },
        highlight = {
          "RainbowDelimiterRed",
          "RainbowDelimiterYellow",
          "RainbowDelimiterBlue",
          "RainbowDelimiterOrange",
          "RainbowDelimiterGreen",
          "RainbowDelimiterViolet",
          "RainbowDelimiterCyan",
        },
      }
    end,
  },
  -- {
  -- 	"lukas-reineke/indent-blankline.nvim",
  -- },

  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      --
      -- scope = { enabled = false },
      bigfile = { enabled = true },
      dashboard = { enabled = true },
      explorer = {
        enabled = true,
        replace_netrw = true,
        hidden = true,
        files = {
          hidden = true,
          ignored = true,
          follow = true,
          root = true,
        },
        trash = true,
        git_status_open = true,
        exclude = {
          ".git",
        },
      },
      indent = {
        enabled = true,
        only_scope = true,
        only_current = false,
        char = "│",
        priority = 3333,
        indent = {
          hl = {

            "SnacksIndent1",
            "SnacksIndent2",
            "SnacksIndent3",
            "SnacksIndent4",
            "SnacksIndent5",
            "SnacksIndent6",
            "SnacksIndent7",
            "SnacksIndent8",
          },
        },
      },
      input = { enabled = true },
      picker = { enabled = true },
      notifier = { enabled = true },
      quickfile = { enabled = true },
      scope = { enabled = true },
      scroll = { enabled = true },
      statuscolumn = { enabled = true },
      words = { enabled = true },
      animate = { enabled = true },
      bufdelete = { enabled = true },
      debug = { enabled = true },
      dim = { enabled = true },
      rename = { enabled = true },
      terminal = { enabled = true },
      toggle = { enabled = true },
      util = { enabled = true },
      win = { enabled = true },
      image = { enabled = true },
      git = { enabled = true },
      gitbrowse = { enabled = true },
      lazygit = { enabled = true },
    },
    keys = {
      {
        "<leader>e",
        function()
          Snacks.explorer({
            replace_netrw = true,
            hidden = true,
            ignored = true,
            follow = true,
            root = true,
            auto_scope = false,
            scope = {
              enabled = false,
            },

            files = {
              hidden = true,
              ignored = true,
              follow = true,
              root = true,
            },
            trash = true,
            git_status_open = true,
            exclude = {
              ".git",
            },
          })
        end,
        desc = "File [e]xplorer",
      },
      {
        "<leader>E",
        function()
          Snacks.explorer({
            replace_netrw = true,
            hidden = true,
            root = false,
            ignored = true,
            follow = true,
            files = {
              hidden = true,
              ignored = true,
              follow = true,
              root = false,
            },
            trash = true,
            git_status_open = true,
            exclude = {
              -- ".git",
            },
          })
        end,
        desc = "File [E]xplorer",
      },
      {
        "<leader>gl",
        function()
          Snacks.lazygit.open({})
        end,
        desc = "[G]it [L]azy",
      },
    },
  },
}
