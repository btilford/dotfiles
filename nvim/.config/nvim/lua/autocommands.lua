-- Show diagnostic details when paused on blank
--
vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
  group = vim.api.nvim_create_augroup("float_diagnostics", { clear = true }),
  callback = function()
    vim.diagnostic.open_float(nil, {
      show_header = true,
      focus = false,
      focusable = false,
      border = "rounded",
    })
  end,
})
-- vim.api.nvim_set_hl(0, "float_diagnostics", { bg = "#222222", fg = "#999999" })
