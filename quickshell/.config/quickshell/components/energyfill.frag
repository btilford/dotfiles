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

    // Flowing plasma in aspect-corrected space
    float aspect = w / h;
    vec2 pp = uv * vec2(aspect, 1.0);
    float t = u_time;
    float n1 = fbm(pp * 5.0 + vec2(t * 0.6, t * 0.25));
    float n2 = fbm(pp * 10.0 - vec2(t * 0.4, t * 0.7) + n1 * 1.5);
    float plasma = n1 * 0.55 + n2 * 0.45;

    // Accent-colored energy; brightness rides the plasma
    vec3 col = u_color * (0.8 + 0.6 * plasma);

    // Occasional hot sparkle streaks
    float sparkle = pow(hash(pp * 60.0 + floor(t * 8.0)), 10.0);
    col += u_color * sparkle * 0.7;

    // No solid backdrop: alpha is plasma-driven, so low-energy regions stay see-through
    float a = mask * u_alpha * clamp(0.25 + 0.6 * plasma + sparkle * 0.4, 0.0, 1.0) * qt_Opacity;
    fragColor = vec4(col * a, a); // premultiplied
}
