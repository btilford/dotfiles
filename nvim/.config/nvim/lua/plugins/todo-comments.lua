return {
  {
    "folke/todo-comments.nvim",
    event = "VimEnter",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = { signs = false },
  },

  {
    "mvolkmann/todo-quickfix.nvim",
    lazy = false, -- load on startup, not just when required
    config = function() end, -- require the plugin and call its setup function
  },
}
