#version 300 es
// Very subtle STATIC sheen for Hyprland (decoration:screen_shader).
//
// Deliberately time-free: Hyprland warns that a screen shader using the `time` uniform
// requires debug:damage_tracking=false, which "massively" increases GPU load (full-screen
// redraw every frame on every output). So this is a fixed light-from-above gradient — a
// soft diagonal catch-light plus a faint crest band — giving surfaces a glassy depth with
// zero per-frame cost. Also no pointer uniform exists in mainline (hyprwm/Hyprland#1502).
//
// The ANIMATED, mouse-reactive glimmer lives in quickshell (components/shimmer.frag),
// where Qt renders only the shell surfaces.

precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 c = texture(tex, v_texcoord);

    // soft key light from the upper-left: brightest corner, falls off diagonally
    float keyl = 1.0 - dot(v_texcoord, vec2(0.55, 0.45));
    keyl = clamp(keyl, 0.0, 1.0);
    keyl = keyl * keyl; // concentrate toward the corner

    // faint fixed crest band across the upper third, like a sheet reflection
    float p = dot(v_texcoord, vec2(0.8, 0.6));
    float band = pow(max(sin(p * 4.2 + 1.1), 0.0), 6.0);

    float sheen = keyl * 0.02 + band * 0.012;
    c.rgb *= 1.0 + sheen;

    fragColor = c;
}
