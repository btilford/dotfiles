#version 440

// Flowing plasma FILL for active-item highlights (workspace pill, active-window indicator).
// Replaces a flat accent rectangle with animated energy in the accent color. Rounded via u_radius.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_width;
    float u_height;
    float u_radius;
    float u_alpha;    // overall fill opacity (keep high for text contrast)
    vec3 u_color;
};

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.0 + vec2(0.13, 0.27);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float w = max(u_width, 1.0);
    float h = max(u_height, 1.0);
    float px = uv.x * w;
    float py = uv.y * h;

    // Rounded-rect coverage mask (anti-aliased 1px edge)
    vec2 hs = vec2(w, h) * 0.5;
    vec2 q = abs(vec2(px, py) - hs) - (hs - vec2(u_radius));
    float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - u_radius;
    float mask = clamp(0.5 - sdf, 0.0, 1.0);

    // Slow bubbly lava: rotating, domain-warped blobby noise. u_time runs 0..2π per loop, and
    // every drift term is an integer multiple of t, so the pattern is seamless across the loop.
    float aspect = w / h;
    vec2 pp = (uv - 0.5) * vec2(aspect, 1.0);
    float t = u_time;
    float c = cos(t), s = sin(t);
    pp = mat2(c, -s, s, c) * pp; // one full rotation per loop

    float n1 = fbm(pp * 3.2 + vec2(sin(t), cos(t)) * 0.7);
    float n2 = fbm(pp * 3.2 + n1 * 1.7 + vec2(cos(2.0 * t), sin(3.0 * t)) * 0.5);
    // mostly-bright lava with small dark bubbles drifting through (reads clearly as "active")
    float bright = smoothstep(0.28, 0.52, n2);

    vec3 col = u_color * (0.7 + 0.55 * bright);

    // high base coverage; dark bubbles dim rather than punch through
    float a = mask * u_alpha * (0.5 + 0.45 * bright) * qt_Opacity;
    fragColor = vec4(col * a, a); // premultiplied
}
