return {
	{ -- Autoformat
		"stevearc/conform.nvim",
		event = {
			-- 'BufWritePre'
		},
		cmd = { "ConformInfo" },
		keys = {
			{
				"<leader>f",
				function()
					require("conform").format({ async = true, lsp_format = "fallback" })
				end,
				mode = "",
				desc = "[F]ormat buffer",
			},
		},
		opts = {
			notify_on_error = false,
			format_on_save = function(bufnr)
				-- Disable "format_on_save lsp_fallback" for languages that don't
				-- have a well standardized coding style. You can add additional
				-- languages here or re-enable it for the disabled ones.
				local disable_filetypes = {
					c = true,
					cpp = true,
				}
				if disable_filetypes[vim.bo[bufnr].filetype] then
					return nil
				else
					return {
						timeout_ms = 500,
						lsp_format = "fallback",
					}
				end
			end,
			formatters = {
				kulala = {
					command = "kulala-fmt",
					args = { "format", "$FILENAME" },
					stdin = false,
				},
			},
			formatters_by_ft = {
				lua = { "stylua" },
				http = { "kulala-fmt" },
				md = { "mdformat" },
				json = { "jq", args = { "--indent", "2", "--compact", "--pretty" } },
				jsonc = { "jq", args = { "--indent", "2", "--compact", "--pretty" } },
				yaml = { "yamlfix" },
				python = { "black" },
				kt = { "ktlint" },
				typescript = { "prettierd", "eslint" },
				javascript = { "prettierd", "eslint" },
				typescriptreact = { "prettierd", "eslint" },
				javascriptreact = { "prettierd", "eslint" },
				tsx = { "prettierd", "eslint" },

				-- Conform can also run multiple formatters sequentially
				-- python = { "isort", "black" },
				--
				-- You can use 'stop_after_first' to run the first available formatter from the list
				-- javascript = { "prettierd", "prettier", stop_after_first = true },
			},
		},
	},
}
