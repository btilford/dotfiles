-- Workspace rules using hl.workspace_rule() API

hl.workspace_rule({
    workspace = "1",
    default = true,
    persistent = true,
    default_name = "Main",
    monitor = "desc:Dell Inc. DELL U3225QE SERIAL",
    layout = "master",
})

hl.workspace_rule({
    workspace = "2",
    persistent = true,
    default_name = "CLI1",
    monitor = "desc: UGD MD180UH",
    layout = "scrolling",
})

hl.workspace_rule({
    workspace = "3",
    persistent = true,
    default_name = "RefLeft",
    monitor = "desc: Dell Inc. DELL S2725QC SERIAL",
    layout = "dwindle",
})

hl.workspace_rule({
    workspace = "4",
    persistent = true,
    default_name = "RefRight",
    monitor = "desc: Dell Inc. DELL S2725QC SERIAL",
    layout = "dwindle",
})

hl.workspace_rule({
    workspace = "5",
    persistent = true,
    default_name = "CLI2",
    monitor = "desc:Dell Inc. DELL U3225QE SERIAL",
    layout = "master",
})

hl.workspace_rule({
    workspace = "6",
    persistent = true,
    default_name = "Draw",
    monitor = "desc: UGD MD180UH",
    layout = "scrolling",
})

hl.workspace_rule({
    workspace = "7",
    persistent = true,
    default_name = "Music",
    monitor = "desc: Dell Inc. DELL S2725QC SERIAL",
    layout = "dwindle",
})

hl.workspace_rule({
    workspace = "8",
    persistent = true,
    default_name = "8",
    monitor = "desc: Dell Inc. DELL S2725QC SERIAL",
    layout = "dwindle",
})

hl.workspace_rule({
    workspace = "9",
    persistent = true,
    default_name = "Other",
    monitor = "desc:Dell Inc. DELL U3225QE SERIAL",
    layout = "scrolling",
})

hl.workspace_rule({
    workspace = "10",
    persistent = true,
    default_name = "Messaging",
    monitor = "desc: UGD MD180UH",
    layout = "scrolling",
})
