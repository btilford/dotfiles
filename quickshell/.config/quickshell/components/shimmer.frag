#version 440

// Subtle animated glimmer for quickshell surfaces, lit from the cursor position.
// A soft warm highlight leans toward the pointer (light-position effect, not tracking),
// and a narrow glimmer band sweeps slowly across the surface. u_time spans 0..2π per
// loop and drift terms are integer multiples of t, so the loop is seamless.
// Masks to the surface shape: rounded rect via u_radius, or the Section trapezoid via
// u_sl/u_sr (same convention as energyborder.frag).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_width;
    float u_height;
    float u_radius;
    float u_sl;        // left slant px (Section trapezoid; 0 = none)
    float u_sr;        // right slant px
    float u_strength;  // overall effect strength (~0.05–0.12)
    float u_lightX;    // light position in item UV space (may be outside 0..1)
    float u_lightY;
};

void main() {
    vec2 uv = qt_TexCoord0;
    float w = max(u_width, 1.0);
    float h = max(u_height, 1.0);
    float px = uv.x * w;
    float py = uv.y * h;

    // coverage mask: trapezoid when slanted, else rounded rect
    float mask;
    if (u_sl + u_sr > 0.5) {
        float dl = (px * h - py * u_sl) / sqrt(h * h + u_sl * u_sl);          // right of left edge
        float dr = ((w - px) * h - py * u_sr) / sqrt(h * h + u_sr * u_sr);    // left of right edge
        mask = clamp(min(min(dl, dr), min(py, h - py)) + 0.5, 0.0, 1.0);
    } else {
        vec2 hs = vec2(w, h) * 0.5;
        vec2 q = abs(vec2(px, py) - hs) - (hs - vec2(u_radius));
        float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - u_radius;
        mask = clamp(0.5 - sdf, 0.0, 1.0);
    }

    float aspect = w / h;
    vec2 pp = uv * vec2(aspect, 1.0);
    float t = u_time;

    // light = cursor position + a gentle idle wander (small Lissajous orbit), so the
    // highlight keeps drifting even when the mouse is still. Integer multiples of t
    // keep the loop seamless.
    vec2 wander = vec2(cos(3.0 * t), sin(2.0 * t)) * 0.10;
    vec2 L = vec2(u_lightX * aspect, u_lightY) + wander;

    // broad soft highlight leaning toward the light, with a slow breathing pulse
    float d = distance(pp, L);
    float spot = exp(-d * d * 1.8) * (0.88 + 0.12 * sin(4.0 * t));

    // slow diagonal glimmer band sweeping the surface, brighter near the light
    float p = dot(uv, vec2(0.8, 0.6));
    float band = pow(max(sin(p * 6.28318 - 2.0 * t), 0.0), 5.0);

    float sheen = spot * 0.55 + band * (0.2 + 0.35 * spot);

    // warm-white light, premultiplied
    float a = mask * u_strength * sheen * qt_Opacity;
    fragColor = vec4(vec3(1.0, 0.93, 0.82) * a, a);
}
