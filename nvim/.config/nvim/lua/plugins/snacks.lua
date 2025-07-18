return {
	{
		"HiPhish/nvim-ts-rainbow2",
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
			bigfile = { enabled = true },
			dashboard = { enabled = false },
			explorer = { enabled = true, hidden = true },
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
			picker = { enabled = false },
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
			lazygit = { enabled = true },
			rename = { enabled = true },
			terminal = { enabled = true },
			toggle = { enabled = true },
			util = { enabled = true },
			win = { enabled = true },
			image = { enabled = true },
			git = {
				enabled = true,
			},
			gitbrowse = {
				enabled = true,
			},
			lazygit = {
				enabled = true,
			},
		},
		keys = {
			{
				"<leader>e",
				function()
					Snacks.explorer({ hidden = true })
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
