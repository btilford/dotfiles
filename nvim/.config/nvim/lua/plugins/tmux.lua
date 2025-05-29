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
			return tmux
		end,
	},
}
