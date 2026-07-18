#version 440

// Quadratic-bezier sibling of energyline.frag, for edge-routed connector lines
// (bar foot → dialog side, arriving perpendicular to the edge). Same plasma band /
// sparkle / halo family; the band follows the curve, wobbled with fbm so it stays
// alive. Points are in quad-local pixels.
//
// Rebuild after editing:
//     /usr/lib/qt6/bin/qsb --qt6 -o components/energycurve.frag.qsb components/energycurve.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_energy;
    float u_thickness;
    float u_width;   // quad px
    float u_height;  // quad px
    float u_time;
    vec2 u_p0;       // curve start (quad-local px)
    vec2 u_p1;       // control point
    vec2 u_p2;       // curve end
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

float dot2(vec2 v) {
    return dot(v, v);
}

// distance to a quadratic bezier + the curve parameter t of the closest point
// (analytic cubic solve — Inigo Quilez's construction)
float sdBezier(vec2 pos, vec2 A, vec2 B, vec2 C, out float outT) {
    vec2 a = B - A;
    vec2 b = A - 2.0 * B + C;
    vec2 c = a * 2.0;
    vec2 d = A - pos;
    // degenerate (collinear) guard — treat as a segment via a nudged control point
    float bb = dot(b, b);
    if (bb < 0.0001) {
        vec2 ab = C - A;
        float t = clamp(dot(pos - A, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
        outT = t;
        return length(pos - (A + ab * t));
    }
    float kk = 1.0 / bb;
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float res = 0.0;
    float t = 0.0;
    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;
    if (h >= 0.0) {
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        vec3 t3 = clamp(vec3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
        float d1 = dot2(d + (c + b * t3.x) * t3.x);
        float d2 = dot2(d + (c + b * t3.y) * t3.y);
        if (d1 < d2) {
            res = d1;
            t = t3.x;
        } else {
            res = d2;
            t = t3.y;
        }
    }
    outT = t;
    return sqrt(res);
}

void main() {
    vec2 px = qt_TexCoord0 * vec2(max(u_width, 1.0), max(u_height, 1.0));
    float t = u_time;

    float ct;
    float d = sdBezier(px, u_p0, u_p1, u_p2, ct);

    // wobble the band around the curve so it reads as plasma, not a plotted path
    float wob = (fbm(vec2(ct * 10.0 + t * 0.7, t * 0.4)) - 0.5) * 2.0;
    d = abs(d + wob * u_thickness * 0.8 * u_energy);

    float band = 1.0 - clamp(d / max(u_thickness, 1.0), 0.0, 1.0);
    float glow = band * band;

    // plasma texture along the curve
    vec2 pp = vec2(ct * 14.0, d / max(u_thickness, 1.0));
    float n1 = fbm(pp * 2.0 + vec2(t * 0.9, t * 0.3));
    float n2 = fbm(pp * 4.0 - vec2(t * 1.3, t * 0.5) + n1 * 2.0);
    float pattern = n1 * 0.4 + n2 * 0.6;

    float sparkle = pow(hash(pp * 80.0 + floor(t * 12.0)), 8.0);
    sparkle *= smoothstep(0.06, 0.0, abs(pattern - 0.5)) * band;

    // melt into the endpoints
    float endFade = smoothstep(0.0, 0.08, ct) * smoothstep(1.0, 0.92, ct);

    float halo = 1.0 - clamp(d / max(u_thickness * 3.0, 1.0), 0.0, 1.0);
    // Clamp the SCALAR intensity before tinting — channel clipping shifts the hue
    float lum = (0.55 + 0.45 * pattern) * glow + sparkle * 0.9 + halo * halo * 0.18;
    vec3 col = u_color * min(lum, 1.0);

    float alpha = u_energy * endFade * (glow * 1.15 + sparkle * 0.5 + halo * halo * 0.22);
    alpha = clamp(alpha, 0.0, 1.0) * qt_Opacity;

    // Qt Quick expects premultiplied alpha
    fragColor = vec4(col * alpha, alpha);
}
