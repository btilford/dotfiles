-- luacheck config for every tracked Lua file in this repo (`mise run lint:lua`).
--
-- Each package here is written against a host that injects globals: Hyprland
-- injects `hl`, Neovim `vim`, yazi `ya`/`cx`/`ui`. Left undeclared, luacheck
-- reports several hundred "accessing undefined variable" warnings and the gate is
-- useless. They are declared rather than silenced — declaring `hl` with its
-- FIELDS means a typo like `hl.dsp.window.clos` is still caught, which is the
-- whole point; a blanket `--globals hl` would not catch it.

std = "lua54"
-- Line length is stylua's, not luacheck's. .stylua.toml sets column_width = 100
-- and lefthook runs stylua on staged files, so wrapping is already gated by the
-- formatter. luacheck's own 120-char check would enforce a second, different
-- limit against the repo's un-formatted backlog (see dotfiles-format-lint-cleanup)
-- — 43 hits today, every one of them a line stylua will rewrap when that cleanup
-- lands. This is the one check delegated elsewhere; nothing else is switched off.
max_line_length = false

files["hyprland/.config/hypr/lua/**/*.lua"] = {
  -- `hl` is generated from the hyprland package's own LuaLS stubs — see
  -- mise-scripts/gen-luacheck-hl-std.sh. Read-only: the compositor owns it.
  -- The path is relative to the working directory, i.e. the repo root, which is
  -- where `mise run lint:lua` and CI both invoke luacheck. A wrong cwd fails
  -- loudly with "cannot open" rather than silently checking nothing.
  read_globals = {
    hl = dofile("mise-scripts/luacheck-hl-std.lua"),
  },
  -- MON is this config's own global: monitors.lua publishes an alias table so
  -- workspaces.lua and keyboard.lua can name monitors without hardcoding the
  -- serials that live in the untracked monitors.local.lua. Writable — monitors.lua
  -- sets it.
  globals = { "MON" },
}

files["nvim/.config/nvim/**/*.lua"] = {
  -- `vim` is mutated, not just read (vim.g.*, vim.opt.*), so it belongs in
  -- globals rather than read_globals. Snacks is set by folke/snacks.nvim.
  globals = { "vim" },
  read_globals = { "Snacks" },
}

files["yazi/**/*.lua"] = {
  -- yazi plugin API: ya/cx/ui are injected, Status and Header are the
  -- extendable UI components a plugin patches.
  globals = { "Status", "Header" },
  read_globals = { "ya", "cx", "ui" },
}
