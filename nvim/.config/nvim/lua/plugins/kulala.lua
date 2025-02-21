return {
  {
		"mistweaverco/kulala.nvim",
		opts = {
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
