-- Floating-layer equivalents of the tmux display-popup bindings, plus the
-- sesh picker, edit-output and a floax-style scratch terminal.

local u = require("util")

-- Simple "run this TUI in a popup at the pane's cwd" actions.
local TUIS = {
  { name = "tuicr_popup", title = "Review Repo (tuicr)", argv = { "tuicr" } },
  { name = "ghdash_popup", title = "GitHub Dashboard (gh dash)", argv = { "gh", "dash" } },
  {
    name = "clipborg_popup",
    title = "Clipboard History (clipborg)",
    argv = { "clipborg", "tui" },
    w = 0.8,
    h = 0.75,
    follow_cwd = false,
  },
  { name = "workmux_dashboard", title = "workmux Dashboard", argv = { "workmux", "dashboard" } },
  {
    name = "workmux_diff",
    title = "workmux Diff",
    argv = { "workmux", "dashboard", "--diff" },
  },
}

for _, t in ipairs(TUIS) do
  rex.action({
    name = t.name,
    title = t.title,
    category = "Popups",
    run = function(ctx)
      u.popup(ctx, t.argv, { w = t.w, h = t.h, follow_cwd = t.follow_cwd })
    end,
  })
end

-- prefix + S: sesh-style picker. Live rex sessions first, then sesh.toml
-- entries and zoxide. rex-sesh needs the client ID to switch the app's view,
-- which only works with Remote Control on (Settings > Server > Client Info).
rex.action({
  name = "sesh",
  title = "Sessions & Projects (sesh)",
  category = "Popups",
  run = function(ctx)
    u.popup(ctx, { "rex-sesh", ctx.client_id or "" }, { w = 0.8, h = 0.7, follow_cwd = false })
  end,
})

-- prefix + E: the pane's screen + scrollback in nvim, in a new tab.
-- Port of edit-output.sh (tmux capture-pane -S -32768 | nvim).
rex.action({
  name = "edit_output",
  title = "Edit Pane Output in nvim",
  category = "Pane",
  run = function(ctx)
    local r, err = rex.block.call(u.TERM, "format", {
      block_id = ctx.block_id,
      format = "text",
      trim = true,
    })
    if r == nil then
      error(err, 0)
    end
    local path = os.tmpname() .. ".sh"
    local f = assert(io.open(path, "w"))
    f:write(r.content or "")
    f:close()
    local _, werr = rex.session.new_window({
      window_label = "edit-output",
      focus = true,
      layout = rex.layout.block({
        flavor = u.SHELL,
        options = { command = { "nvim", "+ normal G$", path }, cwd = u.cwd(ctx.block_id) },
      }),
    })
    if werr ~= nil then
      error(werr, 0)
    end
  end,
})

-- prefix + p: floax. A scratch shell in a floating layer at the pane's cwd.
-- rex's own pane.minimize_floating / pane.float cover the hide/re-show half.
rex.action({
  name = "scratch_float",
  title = "Floating Scratch Shell",
  category = "Popups",
  run = function(ctx)
    u.popup(ctx, nil, { w = 0.8, h = 0.8 })
  end,
})
