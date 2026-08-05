return {
  {
    "romgrk/barbar.nvim",
    dependencies = {
      "lewis6991/gitsigns.nvim", -- OPTIONAL: for git status
      "nvim-tree/nvim-web-devicons", -- OPTIONAL: for file icons
    },
    init = function()
      vim.g.barbar_auto_setup = false
    end,
    opts = {
      -- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
      -- animation = true,
      -- insert_at_start = true,
      -- …etc.
    },
    version = "^1.0.0", -- optional: only update when a new 1.x version is released
  },
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    -- event = "VeryLazy",

    -- Trouble's lsp_document_symbols in the statusline — parked, not wired up.
    -- It used to build `symbols` and then never insert it, so it ran on every
    -- lualine load and discarded the result. Restore as one piece:
    -- opts = function(_, o)
    -- 	local symbols = require("trouble").statusline({
    -- 		mode = "lsp_document_symbols",
    -- 		groups = {},
    -- 		title = false,
    -- 		filter = { range = true },
    -- 		format = "{kind_icon}{symbol.name:Normal}",
    -- 		hl_group = "lualine_c_normal",
    -- 	})
    -- 	table.insert(o.sections.lualine_c, { symbols.get, cond = symbols.has })
    -- end,

    config = function()
      require("lualine").setup({
        options = {
          icons_enabled = true,
          theme = "tokyonight",
          -- theme = "darcubox",
          -- theme = "horizon",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          disabled_filetypes = {
            statusline = {},
            winbar = {},
          },
          ignore_focus = {},
          always_divide_middle = true,
          always_show_tabline = false,
          globalstatus = false,
          refresh = {
            statusline = 100,
            tabline = 100,
            winbar = 100,
          },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { "filename", "windows", "tabs" },
          lualine_x = { "encoding", "fileformat", "filetype" },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { "filename" },
          lualine_x = { "location" },
          lualine_y = {},
          lualine_z = {},
        },
        tabline = {},
        winbar = {},
        inactive_winbar = {},
        extensions = {},
      })
    end,
  },
}
