return {
  {
    "tiagovla/scope.nvim",
    -- config = true,
    config = function()
      require("telescope").load_extension("scope")
    end,
  },
}
