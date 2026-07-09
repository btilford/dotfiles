#version 440

// Water-mirror reflection. Samples the source texture vertically flipped (reflection top
// = source bottom), offset by gentle ripple waves that grow with depth, and faded out
// with depth. A faint glint marks the water line. u_time spans 0..2π per loop and all
// phase terms are integer multiples of t, so the animation loops seamlessly.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_ratio;     // fraction of the source height shown
    float u_strength;  // opacity at the water line
    float u_amp;       // ripple amplitude (uv units)
};
layout(binding = 1) uniform sampler2D u_src;

void main() {
    vec2 uv = qt_TexCoord0;
    float t = u_time;
    float depth = uv.y; // 0 at the water line, 1 at the reflection's far edge

    // layered ripples, stronger with depth (surface farther from the object wobbles more)
    float wob = sin(uv.y * 55.0 - 3.0 * t)
              + 0.6 * sin(uv.y * 21.0 + 2.0 * t + uv.x * 9.0)
              + 0.3 * sin(uv.x * 14.0 - 4.0 * t);
    float wobY = 0.5 * sin(uv.x * 26.0 + 2.0 * t) + 0.3 * sin(uv.x * 7.0 - 3.0 * t);

    vec2 suv;
    suv.x = uv.x + wob * u_amp * (0.2 + depth);
    // flipped sample: reflection row y shows source row 1 - y*ratio
    suv.y = 1.0 - clamp(uv.y + wobY * u_amp, 0.0, 1.0) * u_ratio;
    suv.x = clamp(suv.x, 0.0, 1.0);

    vec4 c = texture(u_src, suv);

    // depth fade, shimmering slightly with the ripples; darken like deep water
    float fade = u_strength * pow(1.0 - depth, 1.8) * (0.9 + 0.1 * wob * 0.33);
    c *= fade;
    c.rgb *= 0.85;

    // faint glint at the water line
    float glint = smoothstep(0.04, 0.0, depth) * 0.10 * u_strength;
    c.rgb += vec3(1.0, 0.93, 0.82) * glint * c.a;

    fragColor = c * qt_Opacity;
}
