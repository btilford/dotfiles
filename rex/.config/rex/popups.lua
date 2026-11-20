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

-- prefix + C-s: the fzf sesh picker in a popup. rex-sesh needs the client ID to
-- switch the app's view, which only works with Remote Control on (Settings > Server > Client Info).
rex.action({
  name = "sesh",
  title = "Sessions & Projects (sesh, fzf)",
  category = "Popups",
  run = function(ctx)
    u.popup(ctx, { "rex-sesh", ctx.client_id or "" }, { w = 0.95, h = 0.7, follow_cwd = false })
  end,
})

-- prefix + S: the same picker in the command palette. Live rex sessions first, then
-- sesh.toml and zoxide entries. It switches through rex.client.queue, so it needs no Remote Control.
local HOME = os.getenv("HOME") or ""

local function tilde(path)
  if HOME ~= "" and path:sub(1, #HOME) == HOME then
    return "~" .. path:sub(#HOME + 1)
  end
  return path
end

rex.action({
  name = "sesh_pick",
  title = "Sessions & Projects (sesh)",
  category = "Sessions",
  run = function()
    local list, err = rex.call("session.list")
    if list == nil then
      error(err, 0)
    end
    local by_label = {}
    for _, s in ipairs(list.sessions or {}) do
      by_label[s.label] = s.session_id
    end

    local items, projects = {}, {}
    for _, s in ipairs(list.sessions or {}) do
      table.insert(
        items,
        { id = s.session_id, title = s.label, subtitle = "rex session", icon = "terminal" }
      )
    end
    local r = u.exec({ "sesh", "list", "--config", "--zoxide", "--hide-duplicates", "--json" })
    local entries = r and r.ok and rex.json.decode(r.stdout) or {}
    for i, e in ipairs(entries) do
      -- zoxide names are paths; label the session with the directory name, as rex-sesh does.
      local label = e.Src == "zoxide" and e.Path:match("([^/]+)/*$") or e.Name
      local id = "sesh:" .. i
      projects[id] = { label = label, path = e.Path, startup = e.StartupCommand }
      -- The palette has a fixed width: zoxide rows show the directory name over its parent,
      -- so long worktree paths split across both lines.
      local parent = tilde(e.Path):match("^(.*)/[^/]+/*$")
      parent = parent == "" and "/" or parent
      table.insert(items, {
        id = id,
        title = e.Src == "zoxide" and label or e.Name,
        subtitle = e.Src == "zoxide" and parent or tilde(e.Path),
        icon = e.Src == "config" and "star" or "folder",
        detail = by_label[label] and "open" or e.Src,
      })
    end

    local pick = rex.ui.pick({
      title = "Sessions & Projects",
      placeholder = "Filter sessions and projects",
      items = items,
    })
    if pick == nil then
      return
    end

    local sid = pick
    local p = projects[pick]
    if p then
      sid = by_label[p.label]
      if sid == nil then
        local options = { cwd = p.path }
        -- Type the startup command into the shell, so a shell stays behind as with sesh.
        if p.startup and p.startup ~= "" then
          options.initial_input = p.startup .. "\r"
        end
        local created, cerr = rex.call("session.create", {
          label = p.label,
          initial_windows = {
            { layout = rex.layout.block({ flavor = u.SHELL, options = options }) },
          },
        })
        if created == nil then
          error(cerr, 0)
        end
        sid = created.session_id
      end
    end
    rex.client.queue("session.select", { session_id = sid })
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
