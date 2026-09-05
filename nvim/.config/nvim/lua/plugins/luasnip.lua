return {
  {
    "L3MON4D3/LuaSnip",
    -- follow latest release.
    version = "v2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
    -- install jsregexp (optional!).
    build = "make install_jsregexp",
    dependencies = { "rafamadriz/friendly-snippets" },

    config = function()
      local ls = require("luasnip")
      -- <C-K> and <C-E> are re-mapped by plugins/ai.lua when minuet loads, which
      -- layers a suggestion check in front of these and calls back into them.
      -- They stay the base behaviour for any machine with AI gated off.
      vim.keymap.set({ "i" }, "<C-K>", function()
        ls.expand()
      end, { desc = "Luasnip: Expand snippet" })
      vim.keymap.set({ "i", "s" }, "<C-L>", function()
        ls.jump(1)
      end, { desc = "Luasnip: Jump forward" })
      vim.keymap.set({ "i", "s" }, "<C-H>", function()
        ls.jump(-1)
      end, { desc = "Luasnip: Jump backward" })
      vim.keymap.set({ "i", "s" }, "<C-E>", function()
        if ls.choice_active() then
          ls.change_choice(1)
        end
      end, { desc = "Luasnip: Change choice" })
    end,
  },
}
