local M = {}

M.TERM = "com.superlogical.terminal"
M.SHELL = "com.superlogical.terminal.shell"

-- Same set tmux.nvim's is_vim regex matches: (view|n?vim?x?)(diff)?
local VIM = {
  view = true,
  vi = true,
  vim = true,
  vimx = true,
  nvim = true,
  nvimx = true,
  vimdiff = true,
  nvimdiff = true,
  viewdiff = true,
}

-- True when the block's foreground process is a vim. Any lookup failure
-- answers false, so the key falls back to moving rex focus rather than
-- vanishing into a terminal that is not listening for it.
function M.is_vim(block_id)
  if not block_id then
    return false
  end
  local r = rex.block.call(M.TERM, "process", { block_id = block_id })
  local name = r and r.foreground and r.foreground.name
  return name ~= nil and VIM[name] == true
end

-- The directory the terminal last reported (OSC 7), as a plain path.
-- `pwd` answers a file:// URI with a host part: file://host/path.
function M.cwd(block_id)
  if not block_id then
    return nil
  end
  local r = rex.block.call(M.TERM, "pwd", { block_id = block_id })
  local uri = r and r.pwd
  if not uri then
    return nil
  end
  local path = uri:match("^file://[^/]*(/.*)$") or uri
  return (path:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- A centred floating layer running argv: rex's display-popup -E.
-- The terminal closes when the program exits, so quit = dismiss.
function M.popup(ctx, argv, opts)
  opts = opts or {}
  local w, h = opts.w or 0.9, opts.h or 0.85
  local cwd = opts.cwd
  if cwd == nil and opts.follow_cwd ~= false then
    cwd = M.cwd(ctx.block_id)
  end
  local r, err = rex.session.new_layer({
    bounds = { (1 - w) / 2, (1 - h) / 2, w, h },
    focus = true,
    layout = rex.layout.block({
      flavor = M.SHELL,
      options = { command = argv, cwd = cwd },
    }),
  })
  if err ~= nil then
    error(err, 0)
  end
  return r
end

return M
