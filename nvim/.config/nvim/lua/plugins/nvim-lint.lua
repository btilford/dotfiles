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
      -- TODO: does this overwrite existing linters or add the md config to them?
      lint.linters["markdownlint-cli2"] = {
        args = {
          "--config",
          vim.fn.expand("~/.markdownlint-cli2.yaml"),
          "--",
        },
      }

      -- betterleaks — replaced gitleaks repo-wide on 2026-08-24. nvim-lint ships
      -- a gitleaks linter but has none for betterleaks, and mason has no package
      -- for it either, so define it here. Same shape as nvim-lint's gitleaks.lua:
      -- betterleaks' `stdin` subcommand takes the same flags and emits the same
      -- JSON fields (RuleID/Description/StartLine/EndLine/StartColumn/EndColumn).
      -- The binary comes from mise (`mise use -g betterleaks@latest`) or brew,
      -- not mason — see the dotfiles metapac groups for why there is no Arch
      -- package.
      lint.linters.betterleaks = {
        name = "betterleaks",
        cmd = "betterleaks",
        stdin = true,
        append_fname = true,
        args = { "stdin", "--report-format=json", "--report-path=-", "--exit-code=0" },
        stream = "stdout",
        ignore_exitcode = false,
        parser = function(output, bufnr, _)
          if output == nil or output == "" then
            return {}
          end
          local ok, decoded = pcall(vim.json.decode, output)
          if not ok or type(decoded) ~= "table" then
            return {}
          end

          local diagnostics = {}
          for _, leak in ipairs(decoded) do
            table.insert(diagnostics, {
              bufnr = bufnr,
              lnum = leak.StartLine - 1,
              end_lnum = leak.EndLine - 1,
              col = leak.StartColumn - 1,
              end_col = leak.EndColumn - 1,
              source = "betterleaks",
              message = leak.Description,
            })
          end
          return diagnostics
        end,
      }

      lint.linters_by_ft = {
        ["*"] = {
          "betterleaks",
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
          -- tfsec scans the entire project tree, not just the current file.
          -- Run manually with :lua require("lint").try_lint("tfsec")
        },
        hcl = {
          "tflint",
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
          "betterleaks",
        },
        commit = {
          "gitlint",
          "betterleaks",
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
        "BufWritePost",
        "InsertLeave",
      }, {
        group = lint_augroup,
        pattern = "*",
        callback = function()
          lint.try_lint()
        end,
      })

      -- Run tfsec manually via <leader>lT in terraform/hcl files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "terraform", "hcl" },
        callback = function()
          vim.keymap.set("n", "<leader>lT", function()
            lint.try_lint("tfsec")
          end, { buffer = true, desc = "[L]int [T]fsec (project-wide)" })
        end,
      })
    end,
  },
}
