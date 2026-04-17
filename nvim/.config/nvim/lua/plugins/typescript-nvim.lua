return {
	{
		"pmizio/typescript-tools.nvim",
		enabled = true,
		dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
		opts = {
			settings = {
				-- Use a separate tsserver instance for diagnostics so IDE features
				-- don't stall while diagnostics are computed
				separate_diagnostic_server = true,

				-- Only publish diagnostics on leaving insert mode, not on every keystroke
				publish_diagnostics = "insert_leave",

				-- Expose all code actions (add missing imports, remove unused, etc.)
				expose_as_code_action = "all",

				-- Mirror of VSCode's typescript.suggest.completeFunctionCalls
				complete_function_calls = true,

				-- "off" | "all" | "implementations_only" | "references_only"
				code_lens = "off",

				tsserver_file_preferences = {
					-- Needed for node_modules resolution and import completions
					includeCompletionsForModuleExports = true,
					importModuleSpecifierPreference = "shortest",
					importModuleSpecifierEnding = "minimal",

					-- Inlay hints (adjust to taste)
					includeInlayParameterNameHints = "literals",
					includeInlayParameterNameHintsWhenArgumentMatchesName = false,
					includeInlayFunctionParameterTypeHints = true,
					includeInlayVariableTypeHints = false,
					includeInlayPropertyDeclarationTypeHints = true,
					includeInlayFunctionLikeReturnTypeHints = true,
					includeInlayEnumMemberValueHints = true,
				},

				tsserver_format_options = {
					allowIncompleteCompletions = false,
					allowRenameOfImportPath = true,
				},
			},
		},
	},
}
