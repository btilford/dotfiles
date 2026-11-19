-- The tmux prefix table, on C-b (tmux's default; .tmux.conf never changes it).
--
-- Keys are written unshifted: `%` is shift+5, `S` is shift+s.
-- Turn on Settings > Terminal > Keyboard > "Show key sequence hints" in the app
-- for a which-key style list after C-b.

local u = require("util")

local P = "ctrl+b>"
local function bind(k, action, args)
  rex.bind(P .. k, action, args)
end

-- C-b C-b sends a literal C-b (the tmux send-prefix behaviour)
bind("ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- ── Windows (rex tabs) ───────────────────────────────────────────────────────
bind("c", "client.tab.new")
bind("n", "client.tab.next")
bind(",", "client.tab.rename")
bind("shift+7", "client.tab.close") -- &
for i = 1, 9 do
  bind(tostring(i), "client.tab.goto", { index = i })
end
-- No prefix+p previous-window: floax owns `p` (below), as in tmux. Use the
-- app's ctrl+shift+tab instead.

-- ── Panes ────────────────────────────────────────────────────────────────────
bind("shift+5", "pane.split", { direction = "right" }) -- %
bind("shift+'", "pane.split", { direction = "down" }) -- "
bind("z", "pane.zoom")
bind("x", "pane.close")
bind("o", "pane.focus_next")
bind(";", "pane.focus_previous")
bind("shift+1", "pane.move_to_new_tab") -- ! break-pane
bind("shift+[", "pane.move.left") -- {  swap-pane -U
bind("shift+]", "pane.move.right") -- }  swap-pane -D
bind("space", "pane.balance")
-- prefix + hjkl fallback (plain focus, never forwarded to vim)
bind("h", "pane.focus.left")
bind("j", "pane.focus.down")
bind("k", "pane.focus.up")
bind("l", "pane.focus.right")

-- ── Sessions ─────────────────────────────────────────────────────────────────
bind("shift+s", "sesh") -- S  sesh picker
bind("s", "session.switch") -- choose-session
bind("w", "session.switch") -- choose-tree
bind("shift+4", "session.rename") -- $
bind("shift+9", "session.previous") -- (
bind("shift+0", "session.next") -- )

-- ── Copy / search ────────────────────────────────────────────────────────────
-- rex has no vi copy-mode. Find + mouse selection ("Copy on selection" in the
-- app replaces tmux-yank) is the nearest thing.
bind("[", "client.find.open")
bind("]", "pane.paste")
bind("f", "client.find.open") -- flash.tmux: no label-jump equivalent

-- ── Config ───────────────────────────────────────────────────────────────────
bind("r", "client.config.reload")

-- ── Popups & tools (same letters as .tmux.conf) ──────────────────────────────
bind("p", "scratch_float") -- floax
bind("shift+e", "edit_output") -- E
-- Tool keys bind only where the tool is installed, as the tmux.conf if-shell guards do.
if u.has("tuicr") then
  bind("shift+p", "tuicr_popup") -- P
end
if u.has("gh") then
  bind("shift+g", "ghdash_popup") -- G
end
if u.has("clipborg") then
  bind("v", "clipborg_popup")
end
-- Agents: rex's Activity sidebar reads agent status natively (program status
-- protocol + the agent hooks), so it takes over from `workmux sidebar`.
bind("b", "client.sidebar.activity.toggle")
if u.has("workmux") then
  bind("e", "workmux_dashboard")
  bind("shift+d", "workmux_diff") -- D
end

-- ── Terminal (from the Ghostty config) ───────────────────────────────────────
-- cmd+k clears the screen, as in Ghostty and iTerm2; the session picker is on C-b s.
rex.bind("cmd+k", "com.superlogical.terminal.clear")
rex.bind("alt+r", "client.config.reload")
rex.bind("ctrl+shift+v", "pane.paste")
rex.bind("ctrl+shift+c", "pane.copy")

-- The app owns these settings, not init.lua. Run this once per Mac from the command palette.
rex.action({
  name = "apply_app_settings",
  title = "Apply Dotfiles App Settings",
  category = "Settings",
  run = function()
    rex.client.queue("client.setting.terminal.keyboard.option", { value = "sends_alt" }) -- M-hjkl
    rex.client.queue("client.setting.terminal.keyboard.sequence_hints", { value = true })
    rex.client.queue("client.setting.terminal.selection.copy_on_select", { value = true })
    -- Glass panes: the nearest match to Ghostty's background-opacity.
    rex.client.queue("client.setting.interface.appearance.style", { value = "glass" })
    rex.client.queue("client.setting.interface.appearance.glass", { value = true })
  end,
})
