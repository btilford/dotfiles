#version 440

// Lava-fill for ICON GLYPHS via `layer.effect`: samples the item's rendered texture (the glyph)
// and uses its alpha as the mask, recoloring the glyph with the slow bubbly lava pattern.
// Same lava math as energyfill.frag; u_time is 0..2π per loop and all drift terms are integer
// multiples of t, so the animation is seamless.

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
    float aspect = max(u_width, 1.0) / max(u_height, 1.0);
    vec2 pp = (uv - 0.5) * vec2(aspect, 1.0);
    float t = u_time;
    float c = cos(t), s = sin(t);
    pp = mat2(c, -s, s, c) * pp;

    // Glyphs are small — scale the lava up so blobs read at icon size
    float n1 = fbm(pp * 4.5 + vec2(sin(t), cos(t)) * 0.7);
    float n2 = fbm(pp * 4.5 + n1 * 1.7 + vec2(cos(2.0 * t), sin(3.0 * t)) * 0.5);
    // mostly-bright with small dark bubbles, matching energyfill.frag
    float bright = smoothstep(0.28, 0.52, n2);

    // Keep the glyph readable: high base brightness, lava adds motion on top
    vec3 col = u_color * (0.75 + 0.5 * bright);

    float srcA = texture(source, uv).a;
    float a = srcA * u_alpha * (0.75 + 0.25 * bright) * qt_Opacity;
    fragColor = vec4(col * a, a); // premultiplied
}
