-- Rex config, modelled on ~/.tmux.conf.
--
-- Rex reads this file on the SERVER. On Linux rex is server-only (the beta has
-- no Linux client), so the keys below take effect in whichever client attaches:
-- Rex for Mac today. The same file serves the Mac's own local server.
--
-- After editing: `rex config check`, then `rex config reload` on the server box.
--
--   util.lua   shared helpers (vim detection, cwd lookup, floating popups)
--   nav.lua    C-hjkl / M-hjkl, vim-aware (the tmux.nvim contract)
--   popups.lua sesh picker, edit-output, tuicr, gh dash, clipborg, scratch
--   keys.lua   the C-b prefix table

require("nav")
require("popups")
require("keys")

-- Machine-local overrides: untracked, loads last so it wins.
-- (`*.local.lua` is a reserved name, see the repo CLAUDE.md.)
local cfg = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/"
local f = io.open(cfg .. "init.local.lua", "r")
if f then
  f:close()
  dofile(cfg .. "init.local.lua")
end
