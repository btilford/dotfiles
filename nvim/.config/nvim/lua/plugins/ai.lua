return {
	{
		"github/copilot.vim",
		config = function()
			vim.g.copilot_no_tab_map = true
			vim.g.copilot_assume_mapped = true
			vim.api.nvim_set_keymap(
				"i",
				"<C-a>",
				"copilot#Accept()",
				{ expr = true, silent = true, noremap = false }
			)

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
			model = "mistral", -- The default model to use.
			quit_map = "q", -- set keymap to close the response window
			retry_map = "<c-r>", -- set keymap to re-send the current prompt
			accept_map = "<c-cr>", -- set keymap to replace the previous selection with the last result
			host = "localhost", -- The host running the Ollama service.
			port = "11434", -- The port on which the Ollama service is listening.
			display_mode = "float", -- The display mode. Can be "float" or "split" or "horizontal-split" or "vertical-split".
			show_prompt = false, -- Shows the prompt submitted to Ollama. Can be true (3 lines) or "full".
			show_model = false, -- Displays which model you are using at the beginning of your chat session.
			no_auto_close = false, -- Never closes the window automatically.
			file = false, -- Write the payload to a temporary file to keep the command short.
			hidden = false, -- Hide the generation window (if true, will implicitly set `prompt.replace = true`), requires Neovim >= 0.10
			init = function()
				pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
			end,
			-- Function to initialize Ollama
			command = function(options)
				local body = { model = options.model, stream = true }
				return "curl --silent --no-buffer -X POST http://"
					.. options.host
					.. ":"
					.. options.port
					.. "/api/chat -d $body"
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
}
