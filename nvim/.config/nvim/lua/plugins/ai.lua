return {
	{
		"NickvanDyke/opencode.nvim",
		dependencies = {
			-- Recommended for `ask()` and `select()`.
			-- Required for `snacks` provider.
			---@module 'snacks' <- Loads `snacks.nvim` types for configuration intellisense.
			{ "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
		},
		config = function()
			---@type opencode.Opts
			vim.g.opencode_opts = {
				-- Your configuration, if any — see `lua/opencode/config.lua`, or "goto definition".
			}

			-- Required for `opts.events.reload`.
			vim.o.autoread = true

			-- Recommended/example keymaps.
			vim.keymap.set({ "n", "x" }, "<A-a>", function()
				require("opencode").ask("@this: ", { submit = true })
			end, { desc = "Ask opencode" })
			vim.keymap.set({ "n", "x" }, "<A-x>", function()
				require("opencode").select()
			end, { desc = "Execute opencode action…" })
			vim.keymap.set({ "n", "x" }, "ga", function()
				require("opencode").prompt("@this")
			end, { desc = "Add to opencode" })
			vim.keymap.set({ "n", "t" }, "<C-.>", function()
				require("opencode").toggle()
			end, { desc = "Toggle opencode" })
			vim.keymap.set("n", "<S-C-u>", function()
				require("opencode").command("session.half.page.up")
			end, { desc = "opencode half page up" })
			vim.keymap.set("n", "<S-C-d>", function()
				require("opencode").command("session.half.page.down")
			end, { desc = "opencode half page down" })
			-- You may want these if you stick with the opinionated "<C-a>" and "<C-x>" above — otherwise consider "<leader>o".
			vim.keymap.set("n", "+", "<C-a>", { desc = "Increment", noremap = true })
			vim.keymap.set("n", "-", "<C-x>", { desc = "Decrement", noremap = true })
		end,
	},
	{
		"github/copilot.vim",
		config = function()
			vim.g.copilot_no_tab_map = true
			vim.g.copilot_assume_mapped = true
			vim.api.nvim_set_keymap("i", "<C-a>", "copilot#Accept()", { expr = true, silent = true, noremap = false })

			vim.api.nvim_set_keymap("i", "<C-m>", "copilot#Next()", { expr = true, silent = true, noremap = false })
			vim.api.nvim_set_keymap("i", "<C-M>", "copilot#Previous()", { expr = true, silent = true, noremap = false })
			vim.api.nvim_set_keymap("i", "<C-x>", "copilot#Clear()", { expr = true, silent = true, noremap = false })
			vim.api.nvim_set_keymap("i", "<C-/>", "copilot#Dismiss()", { expr = true, silent = true, noremap = false })
			vim.api.nvim_set_keymap(
				"i",
				"<C-\\>",
				"copilot#Complete()<Esc><CR>",
				{ expr = true, silent = true, noremap = false }
			)
		end,
	},
	-- Custom Parameters (with defaults)
	{
		-- ka codium
		"David-Kunz/gen.nvim",
		opts = {
			model = "qwen3-coder-next", -- The default model to use.
			quit_map = "q", -- set keymap to close the response window
			retry_map = "<c-r>", -- set keymap to re-send the current prompt
			accept_map = "<c-cr>", -- set keymap to replace the previous selection with the last result
		host = "ollama.example.lan", -- The host running the Ollama service.
		port = "11434", -- The port on which the Ollama service is listening.
			display_mode = "float", -- The display mode. Can be "float" or "split" or "horizontal-split" or "vertical-split".
			show_prompt = false, -- Shows the prompt submitted to Ollama. Can be true (3 lines) or "full".
			show_model = false, -- Displays which model you are using at the beginning of your chat session.
			no_auto_close = false, -- Never closes the window automatically.
			file = false, -- Write the payload to a temporary file to keep the command short.
			hidden = false, -- Hide the generation window (if true, will implicitly set `prompt.replace = true`), requires Neovim >= 0.10
		init = function()
			-- Ollama runs on ollama.example.lan (Windows machine) — no local serve needed
		end,
			-- Function to initialize Ollama
			command = function(options)
				local body = { model = options.model, stream = true }
				return string.format(
					"curl --silent --no-buffer -X POST http://%s:%s/api/chat -d $body",
					options.host,
					options.port
				)
			end,
			-- The command for the Ollama service. You can use placeholders $prompt, $model and $body (shellescaped).
			-- This can also be a command string.
			-- The executed command must return a JSON object with { response, context }
			-- (context property is optional).
			-- list_models = '<omitted lua function>', -- Retrieves a list of model names
			result_filetype = "markdown", -- Configure filetype of the result buffer
			debug = false, -- Prints errors and the command which is run.
		},
	},
	-- {
	-- 	"Exafunction/windsurf.vim",
	-- 	event = "BufEnter",
	-- 	config = function()
	-- 		-- Change '<C-g>' here to any keycode you like.
	-- 		vim.keymap.set("i", "<C-g>", function()
	-- 			return vim.fn["codeium#Accept"]()
	-- 		end, { expr = true, silent = true })
	-- 		vim.keymap.set("i", "<c-;>", function()
	-- 			return vim.fn["codeium#CycleCompletions"](1)
	-- 		end, { expr = true, silent = true })
	-- 		vim.keymap.set("i", "<c-,>", function()
	-- 			return vim.fn["codeium#CycleCompletions"](-1)
	-- 		end, { expr = true, silent = true })
	-- 		vim.keymap.set("i", "<c-x>", function()
	-- 			return vim.fn["codeium#Clear"]()
	-- 		end, { expr = true, silent = true })
	-- 	end,
	-- },
	{
		"olimorris/codecompanion.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
			"echasnovski/mini.diff",
		},
		config = function()
			local map = vim.keymap.set

			map({ "n", "v" }, "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", { desc = "CodeCompanion: Toggle chat" })
			map({ "n", "v" }, "<leader>ca", "<cmd>CodeCompanionActions<cr>", { desc = "CodeCompanion: Actions" })
			map("v", "<leader>ci", "<cmd>CodeCompanion<cr>", { desc = "CodeCompanion: Inline edit" })
			map("v", "<leader>ce", "<cmd>CodeCompanion /explain<cr>", { desc = "CodeCompanion: Explain" })

			require("codecompanion").setup({
				adapters = {
					-- Reasoning/chat model — Windows Ollama (qwen3-coder-next)
					ollama_chat = function()
						return require("codecompanion.adapters").extend("ollama", {
							env = {
								url = "http://ollama.example.lan:11434",
							},
							schema = {
								model       = { default = "qwen3-coder-next" },
								max_tokens  = { default = 8192 },
								temperature = { default = 0.6 },
							},
						})
					end,

					-- Fast completion model — Windows Ollama (qwen2.5-coder:7b)
					ollama_inline = function()
						return require("codecompanion.adapters").extend("ollama", {
							env = {
								url = "http://ollama.example.lan:11434",
							},
							schema = {
								model       = { default = "qwen2.5-coder:7b" },
								max_tokens  = { default = 2048 },
								temperature = { default = 0.2 },
							},
						})
					end,
				},

				strategies = {
					chat   = { adapter = "ollama_chat" },
					inline = { adapter = "ollama_inline" },
					agent  = { adapter = "ollama_chat" },
				},

				display = {
					chat = {
						window = {
							layout = "vertical",
							width  = 0.40,
						},
						show_settings = true,
					},
					diff = { provider = "mini_diff" },
				},

				opts = {
					log_level                  = "ERROR",
					send_code                  = true,
					use_default_actions        = true,
					use_default_prompt_library = true,
				},
			})
		end,
	},

	{
		"milanglacier/minuet-ai.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("minuet").setup({
				provider = "openai_compatible",
				provider_options = {
					openai_compatible = {
						model     = "qwen2.5-coder:7b",
						end_point = "http://ollama.example.lan:11434/v1/chat/completions",
						api_key   = "ollama",
						stream    = true,
						optional  = {
							max_tokens  = 256,
							temperature = 0.2,
							top_p       = 0.95,
							stop        = { "```" },
						},
					},
				},
				context_window = 4096,
				context_ratio  = 0.75,
				throttle       = 1000,
				debounce       = 400,
				notify         = false,
				virtualtext = {
					auto_trigger_ft = {},
					keymap = {
						accept      = "<Tab>",
						accept_line = "<S-Tab>",
						prev        = "<C-,>",
						next        = "<C-.>",
						dismiss     = "<C-e>",
					},
				},
			})

			-- blink.cmp integration — add to your blink config:
			-- sources = {
			--   providers = {
			--     minuet = { name = "minuet", module = "minuet.blink", score_offset = 8 },
			--   },
			--   completion = { enabled_providers = { "lsp", "path", "minuet", "buffer" } },
			-- }
		end,
	},
}
