-- REFERENCE ONLY — this file is never loaded.
--
-- monitors.lua does a guarded `dofile` of monitors.local.lua and nothing else, so
-- this file has no effect on the running desktop. It exists to show the shape of a
-- working configuration.
--
-- It is this desk's real layout with the SERIALS REMOVED: real vendors, real
-- models, real positions, real transforms. Only the serial suffix is replaced,
-- because that is the part identifying specific hardware. Model names are generic
-- products and are kept — they are what makes the two-identical-panels problem
-- legible.
--
-- Per machine:
--
--   cp ~/.config/hypr/lua/monitors.example.lua ~/.config/hypr/lua/monitors.local.lua
--
-- and replace each SERIAL with the real suffix from:
--
--   hyprctl monitors all | grep -E 'Monitor|description'
--
-- The serial is only strictly needed to disambiguate two panels of the same model
-- — the two S2725QC below. With one panel of a model, the prefix matches alone.
--
-- On this setup the real file is not hand-written per machine: the private
-- dotfiles repo owns it and stows it to the same path, so the layout is restored
-- by clone && stow. Either way it never lands in this repo — `*.local.lua` is
-- reserved in .gitignore and .stow-local-ignore, and mise-scripts/no-local-values.sh
-- fails any commit carrying a `desc:` serial.

MON = {
  main = "desc: Dell Inc. DELL U3225QE SERIAL", -- centre 32in, workspace "Main"
  cli = "desc: UGD MD180UH SERIAL", -- portable below centre, "CLI1"
  ref_left = "desc: Dell Inc. DELL S2725QC SERIAL", -- portrait left, "RefLeft"
  ref_right = "desc: Dell Inc. DELL S2725QC SERIAL", -- portrait right, "RefRight"
  glasses = "desc: Nreal XREAL One Pro", -- AR glasses, "XR1".."XR3" (no serial: one pair)
}

-- transform: 0 normal, 1 = 90°, 2 = 180°, 3 = 270°
-- position is in logical (post-scale) coordinates; all 4K panels use scale 1.5
-- so those coordinates stay consistent.

hl.monitor({
  output = MON.ref_left,
  mode = "preferred",
  position = "-1440x0",
  scale = 1.5,
  transform = 1,
})
hl.monitor({ output = MON.main, mode = "preferred", position = "0x300", scale = 1.5, transform = 0 })
hl.monitor({ output = MON.cli, mode = "preferred", position = "0x1740", scale = 1.5, transform = 0 })
hl.monitor({
  output = MON.ref_right,
  mode = "preferred",
  position = "2560x0",
  scale = 1.5,
  transform = 3,
})

-- AR glasses: a virtual 1080p display over DP alt-mode rather than a panel on the
-- desk, plugged in INSTEAD of one of the USB-C sinks. scale 1 rather than the 1.5
-- used elsewhere -- a downscale into 1080p optics costs sharpness where text is
-- already hardest to read.
hl.monitor({
  output = MON.glasses,
  mode = "1920x1080@120",
  position = "4000x0",
  scale = 1,
  transform = 0,
})
