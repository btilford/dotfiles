#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_energy;
    float u_thickness;
    float u_borderWidth;
    float u_borderHeight;
    float u_time;
    float u_sl;       // left slant in px  (0 = vertical edge)
    float u_sr;       // right slant in px (0 = vertical edge)
    float u_skipTop;  // >0.5 = don't glow the top edge (trapezoid tab at screen edge)
    float u_radius;   // corner radius (px) for the rounded-rect path (used when sl==sr==0)
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
    float w = max(u_borderWidth, 1.0);
    float h = max(u_borderHeight, 1.0);
    float px = uv.x * w;
    float py = uv.y * h;

    float d;
    if (u_sl + u_sr > 0.5) {
        // Slanted trapezoid tab: \____/  (sections). Distance to slanted sides + bottom
        // (+ optional top). An unslanted side is flush to the screen edge — no glow there.
        //   left edge : line (0,0)->(sl,h)   right edge : line (w,0)->(w-sr,h)   bottom : y=h
        // The bottom edge is the SEGMENT between the slant feet, not the infinite line —
        // otherwise the glow runs past the feet to the quad corners.
        float bx = clamp(px, u_sl, w - u_sr);
        d = length(vec2(px - bx, h - py));
        if (u_sl > 0.5)
            d = min(d, abs(px * h - py * u_sl) / sqrt(h * h + u_sl * u_sl));
        if (u_sr > 0.5)
            d = min(d, abs((px - w) * h + py * u_sr) / sqrt(h * h + u_sr * u_sr));
        if (u_skipTop < 0.5)
            d = min(d, py);
    } else {
        // Rounded-rectangle outline (dialogs, popouts, windows). |SDF| = distance to the edge.
        vec2 hs = vec2(w, h) * 0.5;
        vec2 q = abs(vec2(px, py) - hs) - (hs - vec2(u_radius));
        float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - u_radius;
        d = abs(sdf);
    }

    // Border band: 1 on the edge, 0 past `thickness` px inward
    float band = 1.0 - clamp(d / max(u_thickness, 1.0), 0.0, 1.0);
    float glow = band * band;

    // Time-varying plasma along the border
    float aspect = w / h;
    vec2 pp = uv * vec2(aspect, 1.0);
    float t = u_time;
    float n1 = fbm(pp * 8.0 + vec2(t * 0.5, t * 0.3));
    float n2 = fbm(pp * 16.0 - vec2(t * 0.8, t * 0.6) + n1 * 2.0);
    float n3 = fbm(pp * 4.0 + vec2(sin(t * 0.2), cos(t * 0.3)) * 3.0);
    float pattern = n2 * 0.6 + n3 * 0.4;

    // Electricity sparkles that flicker over time, only on the band
    float sparkle = pow(hash(pp * 100.0 + floor(t * 12.0)), 8.0);
    sparkle *= smoothstep(0.06, 0.0, abs(pattern - 0.5)) * band;

    vec3 col = u_color * (0.35 + 0.65 * pattern) * glow;
    col += u_color * sparkle * 0.9;

    // Soft outer halo just outside the band
    float halo = 1.0 - clamp(d / max(u_thickness * 3.0, 1.0), 0.0, 1.0);
    col += u_color * halo * halo * 0.12;

    float alpha = u_energy * (glow * 0.85 + sparkle * 0.5 + halo * halo * 0.15);
    alpha = clamp(alpha, 0.0, 1.0) * qt_Opacity;

    // Qt Quick expects premultiplied alpha
    fragColor = vec4(col * alpha, alpha);
}
