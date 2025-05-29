return {

	{
		"2kabhishek/nerdy.nvim",
		dependencies = {
			"folke/snacks.nvim",
		},
		cmd = "Nerdy",
	},
	{ -- Fuzzy Finder (files, lsp, etc)
		"nvim-telescope/telescope.nvim",
		event = "VimEnter",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				-- If encountering errors, see telescope-fzf-native README for installation instructions
				"nvim-telescope/telescope-fzf-native.nvim",

				-- `build` is used to run some command when the plugin is installed/updated.
				-- This is only run then, not every time Neovim starts up.
				build = "make",

				-- `cond` is a condition used to determine whether this plugin should be
				-- installed and loaded.
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
			{ "nvim-telescope/telescope-ui-select.nvim" },
			{
				"nvim-telescope/telescope-file-browser.nvim",
				dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
			},
			-- Useful for getting pretty icons, but requires a Nerd Font.
			{ "nvim-tree/nvim-web-devicons", enabled = vim.g.have_nerd_font },
			{ "cljoly/telescope-repo.nvim" },
		},
		config = function()
			-- Telescope is a fuzzy finder that comes with a lot of different things that
			-- it can fuzzy find! It's more than just a "file finder", it can search
			-- many different aspects of Neovim, your workspace, LSP, and more!
			--
			-- The easiest way to use Telescope, is to start by doing something like:
			--  :Telescope help_tags
			--
			-- After running this command, a window will open up and you're able to
			-- type in the prompt window. You'll see a list of `help_tags` options and
			-- a corresponding preview of the help.
			--
			-- Two important keymaps to use while in Telescope are:
			--  - Insert mode: <c-/>
			--  - Normal mode: ?
			--
			-- This opens a window that shows you all of the keymaps for the current
			-- Telescope picker. This is really useful to discover what Telescope can
			-- do as well as how to actually do it!

			-- [[ Configure Telescope ]]
			-- See `:help telescope` and `:help telescope.setup()`
			local telescope = require("telescope")
			local open_with_trouble = require("trouble.sources.telescope").open
			local add_to_trouble = require("trouble.sources.telescope").add

			telescope.setup({
				defaults = {
					no_ignore = true,
					-- initial_mode = "normal",
				},
				-- You can put your default mappings / updates / etc. in here
				--  All the info you're looking for is in `:help telescope.setup()`
				--
				-- defaults = {
				--   mappings = {
				--     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
				--   },
				-- },
				extensions = {

					repo = {
						list = {
							search_dirs = {
								"~/Projects/",
								"~/dotfiles/",
							},
						},
					},
					["ui-select"] = {
						require("telescope.themes").get_dropdown(),
					},
					file_browser = {
						theme = "ivy",
						hijack_netrw = true,
						mappings = {},
					},
				},
				pickers = {
					colorscheme = {
						enable_preview = true,
					},
					oldfiles = {
						cwd_only = true,
						sort_lastused = true,
						ignore_current_buffer = true,
						prompt_title = "Recent Files",
					},
				},
				path_display = {
					-- "hidden",
					"smart",
				},
				mappings = {
					i = {
						["<c-t>"] = open_with_trouble,
					},
					n = {
						["<c-t>"] = open_with_trouble,
					},
				},
			})

			require("telescope").load_extension("repo")
			-- Enable Telescope extensions if they are installed
			pcall(require("telescope").load_extension, "fzf")
			pcall(require("telescope").load_extension, "ui-select")
			require("telescope").load_extension("nerdy")
			-- See `:help telescope.builtin`
			local builtin = require("telescope.builtin")
			vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "[s]earch [H]elp" })
			vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "[s]earch [K]eymaps" })
			vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "[s]earch [F]iles" })
			vim.keymap.set("n", "<leader>ss", builtin.builtin, { desc = "[s]earch [s]elect Telescope" })
			vim.keymap.set("n", "<leader>sw", builtin.grep_string, { desc = "[s]earch current [W]ord" })
			vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "[s]earch by [G]rep" })
			vim.keymap.set("n", "<leader>sd", builtin.diagnostics, { desc = "[s]earch [D]iagnostics" })
			vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "[s]earch [R]esume" })
			vim.keymap.set("n", "<leader>sv", "<cmd>Telescope repo list<cr>", { desc = "[s]earch [V]CS" })
			vim.keymap.set("n", "<leader>s.", builtin.oldfiles, { desc = '[s]earch Recent Files ("." for repeat)' })
			vim.keymap.set("n", "<leader><leader>", builtin.buffers, { desc = "[ ] Find existing buffers" })
			vim.keymap.set(
				"n",
				"<leader>bf",
				"<cmd>Telescope file_browser path=%:p:h select_buffer=true<cr>",
				{ desc = "[F]ile [B]rowser" }
			)

			-- Slightly advanced example of overriding default behavior and theme
			vim.keymap.set("n", "<leader>/", function()
				-- You can pass additional configuration to Telescope to change the theme, layout, etc.
				builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
					winblend = 10,
					previewer = false,
				}))
			end, { desc = "[/] Fuzzily search in current buffer" })

			-- It's also possible to pass additional configuration options.
			--  See `:help telescope.builtin.live_grep()` for information about particular keys
			vim.keymap.set("n", "<leader>s/", function()
				builtin.live_grep({
					grep_open_files = true,
					prompt_title = "Live Grep in Open Files",
				})
			end, { desc = "[s]earch [/] in Open Files" })

			-- Shortcut for searching your Neovim configuration files
			vim.keymap.set("n", "<leader>sn", function()
				builtin.find_files({ cwd = vim.fn.stdpath("config") })
			end, { desc = "[s]earch [N]eovim files" })

			vim.keymap.set(
				"n",
				"<leader>sa",
				"<cmd>Telescope find_files hidden=true<cr>",
				{ desc = "[s]earc [A]ll (Hidden) Files" }
			)
		end,
	},
}
