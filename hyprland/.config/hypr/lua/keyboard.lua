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
