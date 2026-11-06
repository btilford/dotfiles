return {
  {
    "aserowy/tmux.nvim",
    config = function()
      local tmux = require("tmux").setup({
        copy_sync = {
          enable = false,
        },
        navigation = {
          cycle_navigation = true,
          enable_default_keybindings = true,
          persist_zoom = false,
        },
        resize = {
          enable_default_keybindings = false,
          resize_step_x = 1,
          resize_step_y = 1,
        },
        swap = {
          cycle_navigation = false,
          enable_default_keybindings = true,
        },
      })
      -- Make resize commands match TMUX
      -- vim.keymap.set("n", "<M-h>", tmux.resize_left)
      -- vim.keymap.set("n", "<M-j>", tmux.resize_down)
      -- vim.keymap.set("n", "<M-k>", tmux.resize_up)
      -- vim.keymap.set("n", "<M-l>", tmux.resize_right)

      -- rex: the same contract tmux.nvim gives tmux. Move between vim windows;
      -- at the edge, hand off to rex. The rex half (C-hjkl forwarded to vim
      -- panes) lives in rex/.config/rex/nav.lua. Only when rex is the
      -- innermost multiplexer: tmux inside rex keeps tmux.nvim as-is.
      -- Overrides tmux.nvim's cycle_navigation, which outside tmux would wrap
      -- inside vim and never reach the edge.
      if vim.env.REX_SESSION and not vim.env.TMUX then
        local function rex_nav(dir, wincmd)
          return function()
            local before = vim.fn.winnr()
            vim.cmd("wincmd " .. wincmd)
            if vim.fn.winnr() == before then
              vim.system({ "rex", "focus", "-s", vim.env.REX_SESSION, dir })
            end
          end
        end
        vim.keymap.set("n", "<C-h>", rex_nav("left", "h"), { desc = "Window/rex pane left" })
        vim.keymap.set("n", "<C-j>", rex_nav("down", "j"), { desc = "Window/rex pane down" })
        vim.keymap.set("n", "<C-k>", rex_nav("up", "k"), { desc = "Window/rex pane up" })
        vim.keymap.set("n", "<C-l>", rex_nav("right", "l"), { desc = "Window/rex pane right" })
      end
      return tmux
    end,
  },
}
