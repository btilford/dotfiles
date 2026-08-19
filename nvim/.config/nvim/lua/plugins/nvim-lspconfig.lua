return {
  { "kmonad/kmonad-vim" },
  {
    "nvimtools/none-ls.nvim",
    dependencies = {
      "nvimtools/none-ls-extras.nvim",
    },
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          null_ls.builtins.completion.spell,
          require("none-ls.diagnostics.eslint"),
          null_ls.builtins.diagnostics.yamllint.with({
            extra_args = {
              "--config-data",
              "{rules: {line-length: {max: 120 }}}",
            },
          }),
        },
      })
    end,
  },
  -- use mini.starter instead of alpha
  -- { import = "lazyvim.plugins.extras.ui.mini-starter" },

  -- add jsonls and schemastore packages, and setup treesitter for json, json5 and jsonc
  -- { import = "lazyvim.plugins.extras.lang.json" },

  -- For typescript, LazyVim also includes extra specs to properly setup lspconfig,
  -- treesitter, mason and typescript.nvim. So instead of the above, you can use:
  -- { import = "lazyvim.plugins.extras.lang.typescript" },
  {
    -- Main LSP Configuration
    "neovim/nvim-lspconfig",
    dependencies = {
      -- "jose-elias-alvarez/typescript.nvim",
      -- Automatically install LSPs and related tools to stdpath for Neovim
      -- Mason must be loaded before its dependents so we need to set it up here.
      -- NOTE: `opts = {}` is the same as calling `require('mason').setup({})`
      { "mason-org/mason.nvim", opts = {} },
      "mason-org/mason-lspconfig.nvim",
      "WhoIsSethDaniel/mason-tool-installer.nvim",

      -- Useful status updates for LSP.
      {
        "j-hui/fidget.nvim",
        opts = {
          notification = {
            override_vim_notify = true,
          },
        },
      },

      -- Allows extra capabilities provided by blink.cmp
      "saghen/blink.cmp",
    },
    config = function()
      local home = os.getenv("HOME")
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer, and description for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or "n"
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
          end

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map("grn", vim.lsp.buf.rename, "[R]e[n]ame")

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map("gra", vim.lsp.buf.code_action, "[G]oto Code [A]ction", { "n", "x" })

          -- Find references for the word under your cursor.
          map("grr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")

          -- Jump to the implementation of the word under your cursor.
          --  Useful when your language has ways of declaring types without an actual implementation.
          map("gri", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")

          -- Jump to the definition of the word under your cursor.
          --  This is where a variable was first declared, or where a function is defined, etc.
          --  To jump back, press <C-t>.
          map("grd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map("grD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")

          -- Fuzzy find all the symbols in your current document.
          --  Symbols are things like variables, functions, types, etc.
          map("gO", require("telescope.builtin").lsp_document_symbols, "Open Document Symbols")

          -- Fuzzy find all the symbols in your current workspace.
          --  Similar to document symbols, except searches over your entire project.
          map(
            "gW",
            require("telescope.builtin").lsp_dynamic_workspace_symbols,
            "Open Workspace Symbols"
          )

          -- Jump to the type of the word under your cursor.
          --  Useful when you're not sure what type a variable is and you want to see
          --  the definition of its *type*, not where it was *defined*.
          map("grt", require("telescope.builtin").lsp_type_definitions, "[G]oto [T]ype Definition")
          -- Example key mapping in init.lua or a similar configuration file
          vim.api.nvim_set_keymap(
            "n",
            "<leader>ca",
            "<cmd>lua vim.lsp.buf.code_action()<CR>",
            { noremap = true, silent = true }
          )

          -- This function resolves a difference between neovim nightly (version 0.11) and stable (version 0.10)
          ---@param client vim.lsp.Client
          ---@param method vim.lsp.protocol.Method
          ---@param bufnr? integer Some lsp support methods only in specific files
          ---@return boolean
          local function client_supports_method(client, method, bufnr)
            if vim.fn.has("nvim-0.11") == 1 then
              return client:supports_method(method, bufnr)
            else
              return client.supports_method(method, { bufnr = bufnr })
            end
          end

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if
            client
            and client_supports_method(
              client,
              vim.lsp.protocol.Methods.textDocument_documentHighlight,
              event.buf
            )
          then
            local highlight_augroup =
              vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
            vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd("LspDetach", {
              group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds({
                  group = "kickstart-lsp-highlight",
                  buffer = event2.buf,
                })
              end,
            })
          end

          -- The following code creates a keymap to toggle inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if
            client
            and client_supports_method(
              client,
              vim.lsp.protocol.Methods.textDocument_inlayHint,
              event.buf
            )
          then
            map("<leader>th", function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
            end, "[T]oggle Inlay [H]ints")
          end
        end,
      })

      -- Diagnostic Config
      -- See :help vim.diagnostic.Opts
      vim.diagnostic.config({
        severity_sort = true,
        float = { border = "rounded", source = "if_many" },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = "󰅚 ",
            [vim.diagnostic.severity.WARN] = "󰀪 ",
            [vim.diagnostic.severity.INFO] = "󰋽 ",
            [vim.diagnostic.severity.HINT] = "󰌶 ",
          },
        } or {},
        virtual_text = {
          source = "if_many",
          spacing = 2,
          format = function(diagnostic)
            local diagnostic_message = {
              [vim.diagnostic.severity.ERROR] = diagnostic.message,
              [vim.diagnostic.severity.WARN] = diagnostic.message,
              [vim.diagnostic.severity.INFO] = diagnostic.message,
              [vim.diagnostic.severity.HINT] = diagnostic.message,
            }
            return diagnostic_message[diagnostic.severity]
          end,
        },
      })

      -- LSP servers and clients are able to communicate to each other what features they support.
      --  By default, Neovim doesn't support everything that is in the LSP specification.
      --  When you add blink.cmp, luasnip, etc. Neovim now has *more* capabilities.
      --  So, we create new capabilities with blink.cmp, and then broadcast that to the servers.
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      -- Enable the following language servers
      --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
      --
      --  Add any additional override configuration in the following tables. Available keys are:
      --  - cmd (table): Override the default command used to start the server
      --  - Filetypes (table): Override the default list of associated filetypes for the server
      --  - Capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
      --  - Settings (table): Override the default settings passed when initializing the server.
      --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
      local servers = {
        -- ["kulala_ls"] = {},
        clangd = {},
        marksman = {},
        gopls = {},
        pyright = {},
        kotlin_lsp = {},
        -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
        --
        -- Some languages (like typescript) have entire language plugins that can be useful:
        --    https://github.com/pmizio/typescript-tools.nvim
        --
        -- But for many setups, the LSP (`ts_ls`) will work just fine
        -- ts_ls = {},
        --

        -- harper_ls = {
        -- 	userDictPath = home .. "/.config/harper-ls/dictionary.txt",
        -- 	enable = true,
        -- 	filetypes = {
        -- 		"markdown",
        -- 		"text",
        -- 	},
        -- 	linters = {
        -- 		ToDoHyphen = false,
        -- 	},
        -- 	isolateEnglish = true,
        -- 	markdown = {
        -- 		IgnoreLinkTitle = true,
        -- 	},
        -- },

        -- kotlin_language_server = {
        -- 	filetypes = {
        -- 		"kotlin",
        -- 		"kt",
        -- 		"kts",
        -- 	},
        -- },
        -- tsserver = {},
        lua_ls = {
          -- cmd = { ... },
          -- filetypes = { ... },
          -- capabilities = {},
          settings = {
            Lua = {
              format = {
                enable = true,
                defaultConfig = {
                  indent_style = "space",
                  indent_size = "2",
                },
              },
              hint = {
                arrayIndex = "Enable",
              },
              completion = {
                callSnippet = "Replace",
              },
              -- You can toggle below to ignore lua_ls's noisy `missing-fields` warnings
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
        -- setup = {
        -- 	-- example to setup with typescript.nvim
        -- 	tsserver = function(_, opts)
        -- 		require("typescript").setup({ server = opts })
        -- 		return true
        -- 	end,
        -- 	-- Specify * to use this function as a fallback for any server
        -- 	-- ["*"] = function(server, opts) end,
        -- },
        -- "kulala_ls",
        -- ts_ls = {
        -- 	enabled = false,
        -- },
        -- vtsls = {
        -- 	enable = true,
        -- 	filetypes = {
        -- 		"typescript",
        -- 		"typescriptreact",
        -- 		"typescript.tsx",
        -- 		"javascript",
        -- 		"javascriptreact",
        -- 		"javascript.jsx",
        -- 	},
        -- 	settings = {
        -- 		complete_function_calls = true,
        -- 		vtsls = {
        -- 			enableMoveToFileCodeAction = true,
        -- 			autoUseWorkspaceTsdk = true,
        -- 			experimental = {
        -- 				maxInlayHintLength = 30,
        -- 				completion = {
        -- 					enableServerSideFuzzyMatch = true,
        -- 				},
        -- 			},
        -- 		},
        -- 		typescript = {
        -- 			updateImportsOnFileMove = {
        -- 				enable = "always",
        -- 			},
        -- 			suggest = {
        -- 				completeFunctionCalls = true,
        -- 			},
        -- 			inlayHints = {
        -- 				enumMemberValues = {
        -- 					enabled = true,
        -- 				},
        -- 				functionLikeReturnTypes = {
        -- 					enabled = true,
        -- 				},
        -- 				parameterNames = {
        -- 					enabled = true,
        -- 				},
        -- 				parameterTypes = {
        -- 					enabled = true,
        -- 				},
        -- 				propertyDeclarationTypes = {
        -- 					enabled = true,
        -- 				},
        -- 				variableTypes = {
        -- 					enabled = true,
        -- 				},
        -- 			},
        -- 		},
        -- 	},
        -- },
      }

      -- Ensure the servers and tools above are installed
      --
      -- To check the current status of installed tools and/or manually install
      -- other tools, you can run
      --    :Mason
      --
      -- You can press `g?` for help in this menu.
      --
      -- `mason` had to be setup earlier: to configure its options see the
      -- `dependencies` table for `nvim-lspconfig` above.
      --
      -- You can add other tools here that you want Mason to install
      -- for you, so that they are available from within Neovim.
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        -- debuggers
        "jdtls",
        "kotlin-lsp",
        -- "java-test",
        "js-debug-adapter",
        "kotlin-debug-adapter",
        -- "vscode-java-decompiler",
        "go-debug-adapter",
        "cpptools",
        "chrome-debug-adapter",
        "bash-debug-adapter",
        "debugpy",
        -- linters
        "ansible-lint",
        "ast-grep",
        "checkstyle",
        "cmakelint",
        "commitlint",
        "cpplint",
        "dotenv-linter",
        "editorconfig-checker",
        "flake8",
        "gitleaks",
        "gitlint",
        "hadolint",
        "haml-lint",
        "htmlhint",
        "jsonlint",
        "ktlint",
        "kube-linter",
        "luacheck",
        "markdownlint",
        "misspell",
        "semgrep",
        "shellcheck",
        "shellharden",
        "snyk",
        "sqlfluff",
        "stylelint",
        "systemdlint",
        "tflint",
        "tfsec",
        "yamllint",

        -- formatters
        -- "google-java-format",
        "beautysh",
        "htmlbeautifier",
        "jq",
        "markdown-toc",
        "mdformat",
        "nginx-config-formatter",
        "pgformatter",
        "shfmt",
        "sql-formatter",
        "xmlformatter",
        "yamlfix",
        "stylua", -- Used to format Lua code
      })

      require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

      require("mason-lspconfig").setup({
        ensure_installed = {}, -- Explicitly set to an empty table (Kickstart populates installs via mason-tool-installer)
        automatic_installation = false,
        handlers = {
          function(server_name)
            if server_name ~= "jdtls" then
              local server = servers[server_name] or {}
              -- This handles overriding only values explicitly passed
              -- by the server configuration above. Useful when disabling
              -- certain features of an LSP (for example, turning off formatting for ts_ls)
              server.capabilities =
                vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
              require("lspconfig")[server_name].setup(server)
            end
          end,
        },
      })
    end,
  },
}
