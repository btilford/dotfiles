-- Workspace rules using hl.workspace_rule() API

hl.workspace_rule({
  workspace = "1",
  default = true,
  persistent = true,
  default_name = "Main",
  monitor = MON.main,
})

hl.workspace_rule({
  workspace = "2",
  persistent = true,
  default_name = "CLI1",
  monitor = MON.cli,
})

hl.workspace_rule({
  workspace = "3",
  persistent = true,
  default_name = "RefLeft",
  monitor = MON.ref_left,
})

hl.workspace_rule({
  workspace = "4",
  persistent = true,
  default_name = "RefRight",
  monitor = MON.ref_right,
})

hl.workspace_rule({
  workspace = "5",
  persistent = true,
  default_name = "CLI2",
  monitor = MON.main,
})

hl.workspace_rule({
  workspace = "6",
  persistent = true,
  default_name = "Draw",
  monitor = MON.cli,
})

hl.workspace_rule({
  workspace = "7",
  persistent = true,
  default_name = "Music",
  monitor = MON.ref_left,
})

hl.workspace_rule({
  workspace = "8",
  persistent = true,
  default_name = "8",
  monitor = MON.ref_right,
})

hl.workspace_rule({
  workspace = "9",
  persistent = true,
  default_name = "Other",
  monitor = MON.main,
})

hl.workspace_rule({
  workspace = "10",
  persistent = true,
  default_name = "Messaging",
  monitor = MON.cli,
})

-- AR glasses (XREAL). Three workspaces, deliberately NOT persistent: the glasses
-- are plugged in occasionally, in place of one of the USB-C displays, and three
-- permanently-visible workspaces would sit unused in the bar the rest of the time.
-- With MON.glasses unset (no monitors.local.lua, or a machine with no glasses) the
-- monitor resolves to "" and they are simply unpinned, exactly like every rule
-- above. Layouts for these live in lua/layout-auto.lua.
hl.workspace_rule({
  workspace = "11",
  default_name = "XR1",
  monitor = MON.glasses,
})

hl.workspace_rule({
  workspace = "12",
  default_name = "XR2",
  monitor = MON.glasses,
})

hl.workspace_rule({
  workspace = "13",
  default_name = "XR3",
  monitor = MON.glasses,
})
