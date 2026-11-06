-- Seamless nvim <-> rex pane navigation: the tmux.nvim contract, rebuilt.
--
-- rex side (here): C-hjkl in a vim pane is forwarded to vim; anywhere else it
-- moves rex focus. nvim side (nvim/.../plugins/tmux.lua): C-hjkl moves between
-- vim windows and, at the edge, runs `rex focus <dir>`. So a split is a split,
-- whichever program owns it.
--
-- M-hjkl follows the tmux.nvim tmux plugin too: resize the rex pane, except in
-- vim, which gets the key.
--
-- Actions, not function bindings: rex.client.queue (needed to forward a key or
-- resize through the client) is only allowed inside an action. It also makes
-- them testable: `rex do smart_focus direction=left`.

local u = require("util")

local LETTER = { left = "h", down = "j", up = "k", right = "l" }

rex.action({
  name = "smart_focus",
  title = "Focus Pane (vim-aware)",
  category = "Pane",
  args = { direction = "string" },
  run = function(ctx, args)
    local d = args.direction
    if not LETTER[d] then
      error("direction must be left, down, up or right", 0)
    end
    if u.is_vim(ctx.block_id) then
      rex.client.queue("pane.send_key", { key = "ctrl+" .. LETTER[d] })
      return
    end
    -- no wrap: matches @tmux-nvim-navigation-cycle false
    local _, err = rex.session.focus_direction({ direction = d, wrap = false })
    if err ~= nil then
      error(err, 0)
    end
  end,
})

rex.action({
  name = "smart_resize",
  title = "Resize Pane (vim-aware)",
  category = "Pane",
  args = { direction = "string" },
  repeats = true,
  run = function(ctx, args)
    local d = args.direction
    if not LETTER[d] then
      error("direction must be left, down, up or right", 0)
    end
    if u.is_vim(ctx.block_id) then
      rex.client.queue("pane.send_key", { key = "alt+" .. LETTER[d] })
      return
    end
    rex.client.queue("pane.resize", { direction = d, amount = 1 })
  end,
})

for d, k in pairs(LETTER) do
  rex.bind("ctrl+" .. k, "smart_focus", { direction = d })
  rex.bind("alt+" .. k, "smart_resize", { direction = d })
end
