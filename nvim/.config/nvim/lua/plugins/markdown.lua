return {
    {
        "iamcco/markdown-preview.nvim",
        cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
        ft = { "markdown" },
        build = function()
            vim.fn["mkdp#util#install"]()
        end,
    },
    {
        "epwalsh/obsidian.nvim",
        version = "*",
        lazy = false,
        -- ft = "markdown",
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        opts = {
            daily_notes = {
                folder = "Daily Notes",
                date_format = "%Y/%m/%b-%d-%a",
                --alias_format = "%Y/%m/%b-%d-%a",
                default_tags = {
                    "daily-notes"
                }
            },

            new_notes_location = "Inbox",
            preferred_link_style = "markdown",
            open_notes_in = "vsplit",
            workspaces = {
                {
                    name = "notes",
                    path = "~/Documents/personal-notes/notes/",
                },
            },
        },
    },
    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- if you use the mini.nvim suite
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
        ---@module 'render-markdown'
        ---@type render.md.UserConfig
        opts = {},
        lazy = false,
    }
}
