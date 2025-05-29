return {
	{
		"kevinhwang91/nvim-ufo",
		dependencies = {
			"kevinhwang91/promise-async",
		},
		config = function()
			local lsp = { "lsp", "indent" }
			local ftMap = {
				vim = "indent",
				python = lsp,
				git = "",
				lua = lsp,
				kotlin = lsp,
				java = lsp,
				javascript = lsp,
				typescript = lsp,
				bash = lsp,
				zsh = lsp,
				fish = lsp,
				json = lsp,
				yaml = lsp,
				markdown = lsp,
				html = lsp,
				xml = lsp,
			}
			require("ufo").setup({
				provider_selector = function(bufnr, filetype, buftype)
					-- if you prefer treesitter provider rather than lsp,
					-- return ftMap[filetype] or {'treesitter', 'indent'}
					local provider = ftMap[filetype]
					if provider == nil then
						provider = "indent"
					end
					return provider
					-- refer to ./doc/example.lua for detail
				end,
			})
			vim.keymap.set("n", "zR", require("ufo").openAllFolds)
			vim.keymap.set("n", "zM", require("ufo").closeAllFolds)
			vim.keymap.set("n", "zr", require("ufo").openFoldsExceptKinds)
			vim.keymap.set("n", "zm", require("ufo").closeFoldsWith) -- closeAllFolds == closeFoldsWith(0)
			vim.keymap.set("n", "K", function()
				local winid = require("ufo").peekFoldedLinesUnderCursor()
				if not winid then
					-- choose one of coc.nvim and nvim lsp
					vim.fn.CocActionAsync("definitionHover") -- coc.nvim
					vim.lsp.buf.hover()
				end
			end)
		end,
	},
}
