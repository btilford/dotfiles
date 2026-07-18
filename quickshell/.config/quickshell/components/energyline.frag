#version 440

// 1-D sibling of energyborder.frag: an electric arc along a rotated quad.
// u (x) runs along the line, v (y) across it; the centerline wobbles with fbm
// so it reads as plasma, not a ruler stroke. Ends fade so the line melts into
// the components it connects.
//
// Rebuild after editing:
//     /usr/lib/qt6/bin/qsb --qt6 -o components/energyline.frag.qsb components/energyline.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_energy;
    float u_thickness;
    float u_lineLength;  // px along the line
    float u_lineHeight;  // px across (thickness + glow pad)
    float u_time;
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
    float len = max(u_lineLength, 1.0);
    float hgt = max(u_lineHeight, 1.0);
    float t = u_time;

    // wobbling centerline — amplitude scales with energy and leaves room for the glow
    float wob = (fbm(vec2(uv.x * len / 60.0 + t * 0.7, t * 0.4)) - 0.5) * 2.0;
    float center = 0.5 + wob * 0.5 * ((hgt - u_thickness * 2.0) / hgt) * u_energy;
    float d = abs(uv.y - center) * hgt;

    float band = 1.0 - clamp(d / max(u_thickness, 1.0), 0.0, 1.0);
    float glow = band * band;

    // plasma texture along the arc (same fbm family as energyborder)
    float aspect = len / hgt;
    vec2 pp = vec2(uv.x * aspect, uv.y);
    float n1 = fbm(pp * 2.0 + vec2(t * 0.9, t * 0.3));
    float n2 = fbm(pp * 4.0 - vec2(t * 1.3, t * 0.5) + n1 * 2.0);
    float pattern = n1 * 0.4 + n2 * 0.6;

    // flickering sparkles riding the band
    float sparkle = pow(hash(pp * 80.0 + floor(t * 12.0)), 8.0);
    sparkle *= smoothstep(0.06, 0.0, abs(pattern - 0.5)) * band;

    // melt into the endpoints instead of hard-stopping
    float endFade = smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x);

    float halo = 1.0 - clamp(d / max(u_thickness * 3.0, 1.0), 0.0, 1.0);
    // Clamp the SCALAR intensity before tinting — channel clipping shifts the hue
    float lum = (0.55 + 0.45 * pattern) * glow + sparkle * 0.9 + halo * halo * 0.18;
    vec3 col = u_color * min(lum, 1.0);

    float alpha = u_energy * endFade * (glow * 1.15 + sparkle * 0.5 + halo * halo * 0.22);
    alpha = clamp(alpha, 0.0, 1.0) * qt_Opacity;

    // Qt Quick expects premultiplied alpha
    fragColor = vec4(col * alpha, alpha);
}
