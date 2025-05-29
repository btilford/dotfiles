return {
	{
		"TobinPalmer/pastify.nvim",
		cmd = { "Pastify", "PastifyAfter" },
		config = function()
			require("pastify").setup({
				opts = {
					absolute_path = false,
					relative_path = "",
					-- relative_path = "./assets/",
					-- filename = "",
					save = "local",
					default_ft = "markdown",
					filename = function()
						local name = vim.fn.expand("%:t:r") .. "_" .. os.date("%Y-%m-%d_%H-%M-%S")
						vim.notify("Saving image to " .. name)
						return name
					end,
				},
				ft = {},
			})
			vim.api.nvim_set_keymap("v", "<leader>p", ":PastifyAfter<CR>", { noremap = true, silent = true })
			vim.api.nvim_set_keymap("n", "<leader>p", ":PastifyAfter<CR>", { noremap = true, silent = true })
			vim.api.nvim_set_keymap("n", "<leader>P", ":Pastify<CR>", { noremap = true, silent = true })
		end,
	},
	{ "bullets-vim/bullets.vim" },
	{
		"tadmccorkle/markdown.nvim",
		ft = "markdown", -- or 'event = "VeryLazy"'
		opts = {
			-- configuration here or empty for defaults
		},
	},
	{
		"Nedra1998/nvim-mdlink",
		config = function()
			require("nvim-mdlink").setup({
				keymap = true,
				cmp = false,
			})
		end,
	},
	{
		"hedyhli/outline.nvim",
		lazy = true,
		cmd = { "Outline", "OutlineOpen" },
		keys = { -- Example mapping to toggle outline
			{ "<leader>o", "<cmd>outline<cr>", desc = "toggle outline" },
		},
		opts = {
			-- Your setup opts here
		},
	},
	-- - {
	-- 	"iamcco/markdown-preview.nvim",
	-- 	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	-- 	ft = { "markdown" },
	-- 	build = function()
	-- 		vim.fn["mkdp#util#install"]()
	-- 	end,
	-- },
	{
		"epwalsh/obsidian.nvim",
		version = "*",
		lazy = false,
		-- ft = "markdown",
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		gvopts = {
			ui = { enable = false },
			daily_notes = {
				folder = "Daily Notes",
				date_format = "%Y/%m/%b-%d-%a",
				--alias_format = "%Y/%m/%b-%d-%a",
				default_tags = {
					"daily-notes",
				},
			},

			new_notes_location = "Inbox",
			preferred_link_style = "markdown",
			open_notes_in = "vsplit",
			workspaces = {
				{
					name = "notes",
					path = "~/Documents/personal-notes/notes/",
				},
			},
			completion = {
				nvim_cmp = false,
				min_chars = 2,
			},
			templates = {
				folder = "/Templates",
			},
			picker = {
				name = "telescope.nvim",
				note_mapping = {
					new = "<C-a>",
					insert_link = "<C-l>",
				},
				tag_mappings = {
					tag_note = "<C-a>",
					insert_tag = "<C-t>",
				},
			},
			sort_by = "modified",
			sort_reversed = true,
		},
	},
	{
		"MeanderingProgrammer/render-markdown.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- if you use the mini.nvim suite
		init = function()
			vim.opt_local.wrap = true
			-- local color_sign = "#ebfafa"
			-- Define color variables
			local color1_bg = "#005588"
			local color2_bg = "#885500"
			local color3_bg = "#550088"
			local color4_bg = "#008855"
			local color5_bg = "#558800"
			local color6_bg = "#88cc00"
			local color_fg1 = "#222222"
			local color_fg2 = "#222222"
			local color_fg3 = "#aaaaaa"
			local color_fg4 = "#222222"
			local color_fg5 = "#222222"
			local color_fg6 = "#222222"

			local color_fg = "#999999"
			local colorInline_bg = "#1a1a1a"
			-- Heading colors (when not hovered over), extends through the entire line
			vim.cmd(string.format([[highlight Headline1Bg guifg=%s guibg=%s ]], color_fg1, color1_bg))
			vim.cmd(string.format([[highlight Headline2Bg guifg=%s guibg=%s ]], color_fg2, color2_bg))
			vim.cmd(string.format([[highlight Headline3Bg guifg=%s guibg=%s ]], color_fg3, color3_bg))
			vim.cmd(string.format([[highlight Headline4Bg guifg=%s guibg=%s ]], color_fg4, color4_bg))
			vim.cmd(string.format([[highlight Headline5Bg guifg=%s guibg=%s ]], color_fg5, color5_bg))
			vim.cmd(string.format([[highlight Headline6Bg guifg=%s guibg=%s ]], color_fg6, color6_bg))
			-- Define inline code highlight for markdown
			vim.cmd(string.format([[highlight RenderMarkdownCodeInline guifg=%s guibg=%s]], colorInline_bg, color_fg))
			vim.cmd(string.format([[highlight RenderMarkdownCodeInline guifg=%s]], colorInline_bg))

			-- Highlight for the heading and sign icons (symbol on the left)
			-- I have the sign disabled for now, so this makes no effect
			vim.cmd(string.format([[highlight Headline1Fg cterm=bold gui=bold guifg=%s]], color1_bg))
			vim.cmd(string.format([[highlight Headline2Fg cterm=bold gui=bold guifg=%s]], color2_bg))
			vim.cmd(string.format([[highlight Headline3Fg cterm=bold gui=bold guifg=%s]], color3_bg))
			vim.cmd(string.format([[highlight Headline4Fg cterm=bold gui=bold guifg=%s]], color4_bg))
			vim.cmd(string.format([[highlight Headline5Fg cterm=bold gui=bold guifg=%s]], color5_bg))
			vim.cmd(string.format([[highlight Headline6Fg cterm=bold gui=bold guifg=%s]], color6_bg))
		end,

		-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
		-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
		---@module 'render-markdown'
		---@type render.md.UserConfig
		opts = {
			completions = {
				blink = {
					enabled = true,
				},
			},
			bullet = {
				enabled = true,
			},
			checkbox = {
				enabled = true,
				position = "inline",
				unchecked = {
					-- Replaces '[ ]' of 'task_list_marker_unchecked'
					icon = "   󰄱 ",
					-- Highlight for the unchecked icon
					highlight = "RenderMarkdownUnchecked",
					-- Highlight for item associated with unchecked checkbox
					scope_highlight = nil,
				},
				checked = {
					-- Replaces '[x]' of 'task_list_marker_checked'
					icon = "   󰱒 ",
					-- Highlight for the checked icon
					highlight = "RenderMarkdownChecked",
					-- Highlight for item associated with checked checkbox
					scope_highlight = nil,
				},
			},
			html = {
				-- Turn on / off all HTML rendering
				enabled = true,
				comment = {
					-- Turn on / off HTML comment concealing
					conceal = false,
				},
			},
			-- Add custom icons lamw26wmal
			link = {
				image = vim.g.neovim_mode == "skitty" and "" or "󰥶 ",
				custom = {
					youtu = { pattern = "youtu%.be", icon = "󰗃 " },
				},
			},
			heading = {
				sign = false,
				icons = { "󰎤 ", "󰎧 ", "󰎪 ", "󰎭 ", "󰎱 ", "󰎳 " },
				backgrounds = {
					"Headline1Bg",
					"Headline2Bg",
					"Headline3Bg",
					"Headline4Bg",
					"Headline5Bg",
					"Headline6Bg",
				},
				foregrounds = {
					"Headline1Fg",
					"Headline2Fg",
					"Headline3Fg",
					"Headline4Fg",
					"Headline5Fg",
					"Headline6Fg",
				},
			},
			-- heading = {
			-- 	enabled = true,
			-- 	render_modes = false,
			-- 	atx = true,
			-- 	sign = true,
			-- 	icons = {
			-- 		"󰲡 ",
			-- 		"󰲣 ",
			-- 		"󰲥 ",
			-- 		"󰲧 ",
			-- 		"󰲩 ",
			-- 		"󰲫 ",
			-- 	},
			-- 	position = "overlay",
			-- 	signs = { "󰫎 " },
			-- 	-- Width of the heading background.
			-- 	-- | block | width of the heading text |
			-- 	-- | full  | full width of the window  |
			-- 	-- Can also be a list of the above values evaluated by `clamp(value, context.level)`.
			-- 	width = "full",
			-- 	-- Amount of margin to add to the left of headings.
			-- 	-- Margin available space is computed after accounting for padding.
			-- 	-- If a float < 1 is provided it is treated as a percentage of available window space.
			-- 	-- Can also be a list of numbers evaluated by `clamp(value, context.level)`.
			-- 	left_margin = 0,
			-- 	-- Amount of padding to add to the left of headings.
			-- 	-- Output is evaluated using the same logic as 'left_margin'.
			-- 	left_pad = 0,
			-- 	-- Amount of padding to add to the right of headings when width is 'block'.
			-- 	-- Output is evaluated using the same logic as 'left_margin'.
			-- 	right_pad = 0,
			-- 	-- Minimum width to use for headings when width is 'block'.
			-- 	-- Can also be a list of integers evaluated by `clamp(value, context.level)`.
			-- 	min_width = 0,
			-- 	-- Determines if a border is added above and below headings.
			-- 	-- Can also be a list of booleans evaluated by `clamp(value, context.level)`.
			-- 	border = false,
			-- 	-- Always use virtual lines for heading borders instead of attempting to use empty lines.
			-- 	border_virtual = false,
			-- 	-- Highlight the start of the border using the foreground highlight.
			-- 	border_prefix = false,
			-- 	-- Used above heading for border.
			-- 	above = "▄",
			-- 	-- Used below heading for border.
			-- 	below = "▀",
			-- 	-- Highlight for the heading icon and extends through the entire line.
			-- 	-- Output is evaluated by `clamp(value, context.level)`.
			-- 	backgrounds = {
			-- 		"RenderMarkdownH1Bg",
			-- 		"RenderMarkdownH2Bg",
			-- 		"RenderMarkdownH3Bg",
			-- 		"RenderMarkdownH4Bg",
			-- 		"RenderMarkdownH5Bg",
			-- 		"RenderMarkdownH6Bg",
			-- 	},
			-- 	-- Highlight for the heading and sign icons.
			-- 	-- Output is evaluated using the same logic as 'backgrounds'.
			-- 	foregrounds = {
			-- 		"RenderMarkdownH1",
			-- 		"RenderMarkdownH2",
			-- 		"RenderMarkdownH3",
			-- 		"RenderMarkdownH4",
			-- 		"RenderMarkdownH5",
			-- 		"RenderMarkdownH6",
			-- 	},
			-- 	-- Define custom heading patterns which allow you to override various properties based on
			-- 	-- the contents of a heading.
			-- 	-- The key is for healthcheck and to allow users to change its values, value type below.
			-- 	-- | pattern    | matched against the heading text @see :h lua-patterns |
			-- 	-- | icon       | optional override for the icon                        |
			-- 	-- | background | optional override for the background                  |
			-- 	-- | foreground | optional override for the foreground                  |
			-- 	custom = {},
			-- },
		},
		lazy = false,
	},
	-- {
	-- 	"3rd/diagram.nvim",
	-- 	dependencies = {
	-- 		"3rd/image.nvim",
	-- 	},
	-- 	opts = { -- you can just pass {}, defaults below
	-- 		events = {
	-- 			render_buffer = { "InsertLeave", "BufWinEnter", "TextChanged" },
	-- 			clear_buffer = { "BufLeave" },
	-- 		},
	-- 		renderer_options = {
	-- 			mermaid = {
	-- 				background = nil, -- nil | "transparent" | "white" | "#hex"
	-- 				theme = nil, -- nil | "default" | "dark" | "forest" | "neutral"
	-- 				scale = 1, -- nil | 1 (default) | 2  | 3 | ...
	-- 				width = nil, -- nil | 800 | 400 | ...
	-- 				height = nil, -- nil | 600 | 300 | ...
	-- 			},
	-- 			plantuml = {
	-- 				charset = nil,
	-- 			},
	-- 			d2 = {
	-- 				theme_id = nil,
	-- 				dark_theme_id = nil,
	-- 				scale = nil,
	-- 				layout = nil,
	-- 				sketch = nil,
	-- 			},
	-- 			gnuplot = {
	-- 				size = nil, -- nil | "800,600" | ...
	-- 				font = nil, -- nil | "Arial,12" | ...
	-- 				theme = nil, -- nil | "light" | "dark" | custom theme string
	-- 			},
	-- 		},
	-- 	},
	-- 	config = function()
	-- 		require("diagram").setup({
	-- 			integrations = {
	-- 				require("diagram.integrations.markdown"),
	-- 				require("diagram.integrations.neorg"),
	-- 			},
	-- 			renderer_options = {
	-- 				mermaid = {
	-- 					theme = "forest",
	-- 				},
	-- 				plantuml = {
	-- 					charset = "utf-8",
	-- 				},
	-- 				d2 = {
	-- 					theme_id = 1,
	-- 				},
	-- 				gnuplot = {
	-- 					theme = "dark",
	-- 					size = "800,600",
	-- 				},
	-- 			},
	-- 		})
	-- 	end,
	-- },
}
