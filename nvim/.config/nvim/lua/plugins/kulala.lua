return {
	{
		"mistweaverco/kulala.nvim",
		keys = {
			{ "<leader>Rs", desc = "[R]equest [s]end" },
			{ "<leader>Ra", desc = "[R]equest send [a]ll" },
			{ "<leader>Rb", desc = "[R]equest scratch [b]uffer" },
		},
		ft = { "http", "rest" },

		opts = {
			global_keymaps = false,
			global_keymaps_prefix = "<leader>R",
			kulala_keymaps_prefix = "",
			contenttypes = {
				["application/json"] = {
					ft = "json",
					formatter = { "jq", "." },
					-- pathresolver = require("kulala.parser.jsonpath").parse,
				},
				["application/ld+json"] = {
					ft = "json",
					formatter = { "jq", "." },
					-- pathresolver = require("kulala.parser.jsonpath").parse,
				},
				["application/hal+json"] = {
					ft = "json",
					formatter = { "jq", "." },
					-- pathresolver = require("module 'kulala.parser.jsonpath' not found").parse,
				},
				["application/xml"] = {
					ft = "xml",
					formatter = { "xmllint", "--format", "-" },
					pathresolver = { "xmllint", "--xpath", "{{path}}", "-" },
				},
				["text/html"] = {
					ft = "html",
					formatter = { "xmllint", "--format", "--html", "-" },
					pathresolver = {},
				},
			},
		},
	},
}
