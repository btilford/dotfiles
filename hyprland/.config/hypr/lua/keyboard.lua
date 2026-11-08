-- Keyboard Layout
-- https://wiki.hyprland.org/Configuring/Variables/#input

hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "",
    numlock_by_default = true,
    sensitivity = 1.0,
    accel_profile = "adaptive",
    follow_mouse = 1,
    follow_mouse_threshold = 1.0,
    focus_on_close = 1,
    mouse_refocus = false,
    float_switch_override_focus = 2,
    touchpad = {
      disable_while_typing = true,
      drag_lock = true,
    },
    tablet = {
      output = MON.cli,
    },
  },
})

-- ZMK trackball. Its speed is tuned on the keyboard for macOS, so Linux must not
-- scale it again: the global sensitivity above is the maximum (1.0) for the other
-- mice. Flat + 0.0 passes ZMK's movement through untouched; go negative if fast.
hl.device({
  name = "crosses-bt-mouse",
  sensitivity = 0.0,
  accel_profile = "flat",
})
