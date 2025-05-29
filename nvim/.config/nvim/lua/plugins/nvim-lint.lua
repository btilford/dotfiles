return {
	{
		"mfussenegger/nvim-lint",
		-- https://github.com/mfussenegger/nvim-lint
		event = {
			"BufReadPre",
			"BufNewFile",
		},
		config = function()
			local lint = require("lint")
			lint.linters_by_ft = {
				["*"] = {
					"gitleaks",
					"spellcheck",
				},
				kotlin = {
					"ktlint",
				},
				yaml = {
					"yamllint",
				},
				json = {
					"jsonlint",
				},
				lua = {
					"luacheck",
				},
				python = {
					"flake8",
				},
				javascript = {
					"eslint",
				},
				typescript = {
					"eslint",
				},
				typescriptreact = {
					"eslint",
				},
				["typescript.tsx"] = {
					"eslint",
				},
				html = {
					"htmlhint",
				},
				css = {
					"stylelint",
				},
				scss = {
					"stylelint",
				},
				sass = {
					"stylelint",
				},
				markdown = {
					"markdownlint",
				},
				sh = {
					"shellcheck",
				},
				bash = {
					"shellcheck",
				},
				zsh = {
					"shellcheck",
				},
				dockerfile = {
					"hadolint",
				},
				editorconfig = {
					"editorconfig-checker",
				},
				env = {
					"dotenv-linter",
				},
				haml = {
					"hamllint",
				},
				terraform = {
					"tflint",
					"tfsec",
					"hclint",
				},
				hcl = {
					"hclint",
					"tflint",
					"tfsec",
				},
				playbook = {
					"ansiblelint",
				},
				["ansible.yaml"] = {
					"ansiblelint",
				},
				["ansible.yml"] = {
					"ansiblelint",
				},
				["ansible.yaml.j2"] = {
					"ansiblelint",
				},
				["ansible.yml.j2"] = {
					"ansiblelint",
				},
				["ansible.j2"] = {
					"ansiblelint",
				},
				["ansible.jinja"] = {
					"ansiblelint",
				},
				["ansible.jinja2"] = {
					"ansiblelint",
				},
				["ansible.j2.jinja"] = {
					"ansiblelint",
				},
				["ansible.j2.jinja2"] = {
					"ansiblelint",
				},
				["ansible.jinja.j2"] = {
					"ansiblelint",
				},
				["ansible.jinja2.j2"] = {
					"ansiblelint",
				},
				java = {
					"checkstyle",
				},
				precommit = {
					"gitleaks",
				},
				commit = {
					"gitlint",
					"gitleaks",
				},
				commit_msg = {
					"gitlint",
				},
				json5 = {
					"jsonlint",
				},
				sql = {
					"sqlfluff",
				},
				["sql.sql"] = {
					"sqlfluff",
				},
				["sql.sqlx"] = {
					"sqlfluff",
				},
				["sql.sqlx.sql"] = {
					"sqlfluff",
				},

				["systemd.unit"] = {
					"systemd-lint",
				},
				["systemd.service"] = {
					"systemd-lint",
				},
				["systemd.socket"] = {
					"systemd-lint",
				},
				["systemd.timer"] = {
					"systemd-lint",
				},
				["systemd.mount"] = {
					"systemd-lint",
				},
				["systemd.automount"] = {
					"systemd-lint",
				},
			}
			local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
			vim.api.nvim_create_autocmd({
				"BufEnter",
				"BufWritePost",
				"InsertLeave",
			}, {
				group = lint_augroup,
				pattern = "*",
				callback = function()
					lint.try_lint()
				end,
			})
		end,
	},
}
