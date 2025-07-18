return {
	{
		"mistweaverco/kulala.nvim",
		-- keys = {
		-- 	{ "<leader>Rs", desc = "[R]equest [s]end" },
		-- 	{ "<leader>Ra", desc = "[R]equest send [a]ll" },
		-- 	{ "<leader>Rb", desc = "[R]equest scratch [b]uffer" },
		-- },
		ft = { "http", "rest" },

		opts = {
			global_keymaps = true,
			global_keymaps_prefix = "<leader>K",
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
		config = function()
			local kulala = require("kulala")
			kulala.setup()

			vim.keymap.set("n", "<leader>Rs", function()
				kulala.run()
			end, { desc = "[R]equest [s]end" })

			vim.keymap.set("n", "<leader>Ra", function()
				kulala.run_all()
			end, { desc = "[R]equest [a]ll" })

			vim.keymap.set("n", "<leader>Rr", function()
				kulala.replay()
			end, { desc = "[R]equest [r]eplay" })

			vim.keymap.set("n", "<leader>Re", function()
				kulala.set_selected_env()
			end, { desc = "[R]equest [e]nvironment" })

			vim.keymap.set("n", "<leader>Rcc", function()
				kulala.copy()
			end, { desc = "[R]equest [c]opy as [c]url" })

			vim.keymap.set("n", "<leader>Rpc", function()
				kulala.copy()
			end, { desc = "[R]equest [p]aste from [c]url" })

			vim.keymap.set("n", "<leader>sR", function()
				kulala.copy()
			end, { desc = "[s]earch [R]equests" })

			vim.keymap.set("n", "<leader>Ru", function()
				require("kulala.ui.auth_manager").open_auth_config()
			end, { desc = "[R]equest [u]pdate auth." })
		end,
	},
}
