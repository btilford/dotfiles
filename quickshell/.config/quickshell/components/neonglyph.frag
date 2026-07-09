#version 440

// NEON recolor for icon glyphs via `layer.effect`: the glyph body becomes a white-hot core in
// the accent color with a colored glow sampled around it, plus the same mains-buzz flicker as
// neonfill.frag. Same uniform block as energyglyph.frag (the lava variant, kept for later)
// so EnergyGlyph.qml can swap between them.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_width;
    float u_height;
    float u_alpha;
    vec3 u_color;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    float t = u_time;

    // mains buzz + rare dips (matches neonfill.frag; slow + subtle)
    float buzz = 0.95 + 0.05 * sin(10.0 * t) * sin(16.0 * t);
    float dip = 1.0 - 0.22 * smoothstep(0.985, 1.0, sin(2.0 * t) * sin(6.0 * t));
    float I = buzz * dip;

    float srcA = texture(source, uv).a;

    // colored halo: sample the glyph alpha in a small ring around this texel
    vec2 r = vec2(2.5) / vec2(max(u_width, 1.0), max(u_height, 1.0));
    float g = 0.0;
    g += texture(source, uv + vec2(r.x, 0.0)).a;
    g += texture(source, uv - vec2(r.x, 0.0)).a;
    g += texture(source, uv + vec2(0.0, r.y)).a;
    g += texture(source, uv - vec2(0.0, r.y)).a;
    g += texture(source, uv + r * 0.707).a;
    g += texture(source, uv - r * 0.707).a;
    g += texture(source, uv + vec2(r.x, -r.y) * 0.707).a;
    g += texture(source, uv + vec2(-r.x, r.y) * 0.707).a;
    float halo = clamp(g * 0.22, 0.0, 1.0) * (1.0 - srcA);

    vec3 core = mix(u_color, vec3(1.0), 0.45); // white-hot glyph body
    vec3 col = core * srcA + u_color * halo;

    float a = (srcA * 0.95 + halo * 0.6) * u_alpha * I * qt_Opacity;
    a = clamp(a, 0.0, 1.0);
    fragColor = vec4(col * a, a); // premultiplied
}
