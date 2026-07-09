#version 440

// NEON fill for active-item highlights: a bright tube line hugging the shape's edge with a
// colored glow bleeding inward, white-hot core color, and a subtle mains-buzz flicker with
// occasional dips — like a lit neon sign in the accent color. Interior stays mostly
// transparent so the item reads as outlined-in-neon rather than filled.
// Same uniform block as energyfill.frag (the lava variant, kept for later) so EnergyFill.qml
// can swap between them. u_time spans 0..2π per loop; all terms are integer multiples of t.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_width;
    float u_height;
    float u_radius;
    float u_alpha;
    vec3 u_color;
};

void main() {
    vec2 uv = qt_TexCoord0;
    float w = max(u_width, 1.0);
    float h = max(u_height, 1.0);
    float px = uv.x * w;
    float py = uv.y * h;

    // rounded-rect SDF (negative inside)
    vec2 hs = vec2(w, h) * 0.5;
    vec2 q = abs(vec2(px, py) - hs) - (hs - vec2(u_radius));
    float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - u_radius;
    float mask = clamp(0.5 - sdf, 0.0, 1.0);
    float dIn = max(-sdf, 0.0); // distance inward from the edge, px

    float t = u_time;

    // mains buzz: fast shallow oscillation + rare brief dips (kept subtle)
    float buzz = 0.95 + 0.05 * sin(40.0 * t) * sin(64.0 * t);
    float dip = 1.0 - 0.22 * smoothstep(0.985, 1.0, sin(9.0 * t) * sin(23.0 * t));
    float I = buzz * dip;

    // bright tube line ~1.5px inside the edge
    float tube = smoothstep(2.5, 0.5, abs(dIn - 1.5));
    // colored glow bleeding inward from the tube
    float glow = exp(-dIn / max(min(w, h) * 0.22, 3.0));

    // filled tube: glowing interior, brighter toward the edges, white-hot rim
    vec3 core = mix(u_color, vec3(1.0), 0.55);
    vec3 col = core * tube + u_color * (0.85 + 0.3 * glow);

    float a = mask * u_alpha * (0.5 + glow * 0.25 + tube * 0.45) * I * qt_Opacity;
    a = clamp(a, 0.0, 1.0);
    fragColor = vec4(col * a, a); // premultiplied
}
