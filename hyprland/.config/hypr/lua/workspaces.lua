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
