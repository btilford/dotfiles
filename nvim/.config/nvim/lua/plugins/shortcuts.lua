return {
	{
		"tris203/precognition.nvim",
		event = "VeryLazy",
		opts = {
			-- startVisible = true,
			-- showBlankVirtLine = true,
			-- highlightColor = { link = "Comment" },
			-- hints = {
			--      Caret = { text = "^", prio = 2 },
			--      Dollar = { text = "$", prio = 1 },
			--      MatchingPair = { text = "%", prio = 5 },
			--      Zero = { text = "0", prio = 1 },
			--      w = { text = "w", prio = 10 },
			--      b = { text = "b", prio = 9 },
			--      e = { text = "e", prio = 8 },
			--      W = { text = "W", prio = 7 },
			--      B = { text = "B", prio = 6 },
			--      E = { text = "E", prio = 5 },
			-- },
			-- gutterHints = {
			--     G = { text = "G", prio = 10 },
			--     gg = { text = "gg", prio = 9 },
			--     PrevParagraph = { text = "{", prio = 8 },
			--     NextParagraph = { text = "}", prio = 8 },
			-- },
			-- disabled_fts = {
			--     "startify",
			-- },
		},
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		---@type Flash.Config
		opts = {},
		keys = {
			-- TODO use other keybindings
			{
				"<leader>Fj",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "[F]lash [j]ump",
			},
			{
				"<leader>Ft",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "[F]lash [t]reesitter",
			},
			{
				"<leader>Fr",
				mode = "o",
				function()
					require("flash").remote()
				end,
				desc = "[F]lash [r]emote",
			},
			{
				"<leader>FR",
				mode = { "o", "x" },
				function()
					require("flash").treesitter_search()
				end,
				desc = "[F]lash [R]emote Treesitter Search",
			},
			{
				"<c-s>",
				mode = { "c" },
				function()
					require("flash").toggle()
				end,
				desc = "Toggle Flash [s]earch",
			},
		},
	},
	{
		"m4xshen/hardtime.nvim",
		lazy = "VeryLazy",

		dependencies = { "MunifTanjim/nui.nvim" },
		opts = {
			enable = true,
			max_count = 7,
			max_time = 1200,
			disable_mouse = false,
			hint = true,
			allow_different_key = true,
			restriction_mode = "hint",
			disabled_file_types = {},

			disabled_keys = {
				["<Up>"] = { "n" },
				["<Down>"] = { "n" },
				["<Left>"] = { "n" },
				["<Right>"] = { "n" },
			},
		},
	},
}
