-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local lspconfig = require "lspconfig"

-- EXAMPLE
local servers = {
  "html",
  "cssls",
  "nixd",
  "nushell",
  "bashls",
  "cmake",
  "css_variables",
  "cssmodules_ls",
  "dartls",
  "denols",
  "eslint",
  "fish_lsp",
  "groovyls",
  "graphql",
  "grammarly",
  "htmx",
  "java_language_server",
  "jinja_lsp",
  "jqls",
  "jsonls",
  "kotlin_language_server",
  "matlab_ls",
  "nginx_language_server",
  "openscad_ls",
  "postgres_lsp",
  "puppet",
  "pylsp",
  -- "robocop",
  "sqlls",
  "svelte",
  "terraform_lsp",
  "ts_ls",
  "yamlls",
  "helm_ls",
}
local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

-- configuring single server, example: typescript
-- lspconfig.ts_ls.setup {
--   on_attach = nvlsp.on_attach,
--   on_init = nvlsp.on_init,
--   capabilities = nvlsp.capabilities,
-- }
