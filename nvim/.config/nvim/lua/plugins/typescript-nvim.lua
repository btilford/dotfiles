return {
	{
		"pmizio/typescript-tools.nvim",
		enabled = true,
		dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
		opts = {
			complete_function_calls = true,
			code_lens = "on",
		},
	},
}
