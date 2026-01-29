return {
	{
		"bennypowers/nvim-regexplainer",

		config = function()
			require("regexplainer").setup({})
			--
			-- 	mode = "graphical",
			-- 	display = "popup",
			-- 	deps = {
			-- 		auto_install = true,
			-- 	},
			-- 	auto = true,
			-- 	filetypes = {
			-- 		"lua",
			-- 		"python",
			-- 		"javascript",
			-- 		"typescript",
			-- 		"java",
			-- 		"c",
			-- 		"cpp",
			-- 		"rust",
			-- 		"go",
			-- 		"ruby",
			-- 		"php",
			-- 		"html",
			-- 		"css",
			-- 		"json",
			-- 		"yaml",
			-- 		"markdown",
			-- 		"kotlin",
			-- 	},
			-- 	mappings = {
			-- 		toggle = "grx",
			-- 		explain = "gRx",
			-- 	},
			-- })
		end,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"MunifTanjim/nui.nvim",
		},
	},
}
