-- Example for lua/obsidian-workspaces.lua, the untracked module that
-- lua/plugins/markdown.lua reads. Vault paths name an employer and a personal
-- directory layout, so they stay out of this repo.
--
-- Copy it to ~/.config/nvim/lua/obsidian-workspaces.lua and edit the paths.
-- Stow runs with --no-folding, so a real file survives beside the symlinks.
-- obsidian.nvim does not load when the module is absent or returns no entry.

---@type { name: string, path: string }[]
local workspaces = {}

for _, workspace in ipairs({
  { name = "notes", path = "~/Documents/notes" },
  { name = "work", path = "~/Projects/<employer>/notes" },
}) do
  if vim.fn.isdirectory(vim.fn.expand(workspace.path)) == 1 then
    workspaces[#workspaces + 1] = workspace
  end
end

return workspaces
