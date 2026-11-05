#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The web player's glass (the WebGL fragment shader in index.html, "glass"), for the native panel.
// The layer is the wallpaper exactly as it sits behind the panel, lightly blurred, with a margin m round the panel so
// the rim can pull in what's just outside it.

// rounded rectangle: signed distance + outward normal
static float rr(float2 p, float2 panel, float R, thread float2 &n) {
    float2 c = panel * 0.5, d = p - c, hs = c - R, q = abs(d) - hs;
    float2 sg = float2(d.x >= 0 ? 1 : -1, d.y >= 0 ? 1 : -1);
    if (q.x > 0 && q.y > 0) {
        float2 v = p - (c + sg * hs); float l = length(v);
        n = l > 1e-4 ? v / l : normalize(sg);
        return l - R;
    }
    n = q.x > q.y ? float2(sg.x, 0) : float2(0, sg.y);
    return max(q.x, q.y) - R;
}

// exactly the CSS glass's layers: saturate(135%) brightness(.94); bright wallpaper smoked down (a soft knee) so white
// text stays readable; then the tint towards rgb(6, 18, 26)
static float3 glassy(float3 c, float tint) {
    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = clamp(mix(float3(l), c, 1.35), 0.0, 1.0) * 0.94;
    float lb = dot(c, float3(0.2126, 0.7152, 0.0722));
    if (lb > 0.3) c *= (0.3 + (lb - 0.3) * 0.16) / lb;
    return mix(c, float3(6.0, 18.0, 26.0) / 255.0, tint);
}

[[ stitchable ]] half4 webGlass(float2 pos, SwiftUI::Layer layer, float2 panel, float m, float R,
                                float bevel, float refr, float2 light, float tint) {
    float2 cp = pos - m, n;
    float sd = rr(cp, panel, R, n);
    float din = max(0.0, -sd), t = clamp(1.0 - din / bevel, 0.0, 1.0);
    float3 base = glassy(float3(layer.sample(pos).rgb), tint);
    if (t <= 0.0) return half4(half3(base), 1.0h);
    // rounded edge: the closer to the rim, the more it bends, with a slight colour split
    float bend = refr * (1.0 - sqrt(max(0.0, 1.0 - t * t)));
    float3 raw = float3(layer.sample(pos - n * bend).r, layer.sample(pos - n * bend * 1.05).g, layer.sample(pos - n * bend * 1.1).b);
    float3 col = glassy(raw, tint);
    float ring = smoothstep(0.0, 1.0, t);
    // a thin rim line + a narrow specular on the lit side only
    float sp = pow(max(0.0, dot(n, light)), 2.0) + 0.5 * pow(max(0.0, dot(n, -light)), 2.5);
    float hl = min(1.0, exp(-din / 0.8) * (0.1 + 0.45 * sp) + pow(t, 6.0) * 0.12 * sp);
    float3 rgb = mix(base, col, ring) * (1.0 - hl) + float3(hl);
    return half4(half3(rgb), 1.0h);
}
