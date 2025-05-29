return {
	{
		"rmagatti/auto-session",
		lazy = false,

		---enables autocomplete for opts
		---@module "auto-session"
		---@type AutoSession.Config
		config = function()
			local autoSession = require("auto-session")

			autoSession.setup({
				suppressed_dirs = {
					"~/",
					"~/Projects",
					"~/Downloads",
					"/",
				},
				-- log_level = 'debug',
				auto_session_use_git_branch = false,
				auto_session_enable_last_session = true,
				session_lens = {
					load_on_setup = true,
					previewer = false,
				},
			})
			vim.keymap.set("n", "<leader>Sl", require("auto-session.session-lens").search_session, {
				desc = "[S]ession [l]oad",
				noremap = true,
			})
		end,
	},
	-- {
	-- 	"stevearc/resession.nvim",
	-- 	config = function()
	-- 		local resession = require("resession")
	-- 		vim.api.nvim_create_autocmd("VimLeavePre", {
	-- 			callback = function()
	-- 				resession.save("last")
	-- 			end,
	-- 		})
	-- 		resession.setup({
	-- 			autosave = {
	-- 				enabled = true,
	-- 				interval = 60,
	-- 				notify = true,
	-- 			},
	-- 		})
	--
	-- 		vim.keymap.set("n", "<leader>Ss", resession.save, { desc = "[S]ession [S]ave" })
	-- 		vim.keymap.set("n", "<leader>Sl", resession.load, { desc = "[S]ession [L]oad" })
	-- 		vim.keymap.set("n", "<leader>Sd", resession.delete, { desc = "[S]ession [D]elete" })
	-- 	end,
	-- },
}
