return {
  {
    "nvim-treesitter/nvim-treesitter-context",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("treesitter-context").setup()
    end,
  },
  { -- Highlight, edit, and navigate code
    -- NOTE: main branch is a full rewrite for nvim 0.12+. Highlighting is
    -- now handled natively by neovim; this plugin manages parsers + queries.
    -- master branch has TSNode:range() API incompatibility with nvim 0.12.
    "nvim-treesitter/nvim-treesitter",
    lazy = false, -- must not be lazy loaded (required by main branch)
    branch = "main",
    build = ":TSUpdate",
    config = function()
      -- Prepend install_dir to rtp so user-installed parsers take priority
      -- over the stale pre-compiled parsers bundled in the plugin directory.
      require("nvim-treesitter").setup({
        install_dir = vim.fn.stdpath("data") .. "/site",
      })

      -- Install parsers asynchronously on startup.
      -- Requires: tree-sitter-cli + C compiler (clang/gcc).
      require("nvim-treesitter").install({
        "bash",
        "c",
        "lua",
        "luadoc",
        "python",
        "vim",
        "vimdoc",
        "markdown",
        "markdown_inline",
        "query",
        "diff",
        "typescript",
        "tsx",
        "javascript",
        "html",
        "css",
        "json",
        "yaml",
        "toml",
        "xml",
        "sql",
        "go",
        "java",
        "kotlin",
        "git_config",
        "gitcommit",
        "gitignore",
        "git_rebase",
        "gitattributes",
        "dockerfile",
        "fish",
        "tmux",
        "regex",
        -- "dot" removed: tree-sitter-dot repo has broken branch structure
      })
    end,
  },
}
