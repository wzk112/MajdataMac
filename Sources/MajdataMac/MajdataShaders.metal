#include <metal_stdlib>
using namespace metal;

// CanvasAllPerfect uses the Minimoon SDF atlas with TMP's outline/glow material.
// The importer retains the atlas values and material parameters from MajdataView.
[[ stitchable ]] half4 allPerfectGlyph(float2 position, half4 sample, float2 size, float scale,
    float4 topLeft, float4 topRight, float4 bottomLeft, float4 bottomRight,
    float4 outlineColor, float outlineWidth, float4 glow) {
    float2 uv = clamp(position / size, 0.0, 1.0);
    float4 tint = mix(mix(topLeft, topRight, uv.x), mix(bottomLeft, bottomRight, uv.x), uv.y);
    // Opaque RGB stores the distance field. Use raw atlas values, not image alpha.
    float distance = (0.5 - float(sample.r)) * scale + 0.5;
    float outline = outlineWidth * scale;
    float coverage = 1.0 - clamp(distance - outline * 0.5, 0.0, 1.0);
    float edge = clamp(distance + outline * 0.5, 0.0, 1.0) * sqrt(min(1.0, outline));
    float4 color = mix(float4(tint.rgb, 1), outlineColor, edge) * coverage;
    float halo = distance - glow.x * 0.5 * scale;
    float thickness = (halo >= 0 ? glow.z : glow.y) * 0.5 * scale;
    float strength = (1.0 - pow(clamp(abs(halo / (1.0 + thickness)), 0.0, 1.0), glow.w)) * sqrt(min(1.0, thickness));
    color.rgb += clamp(strength * 2.0, 0.0, 1.0);
    return half4(color * tint.a);
}

// Port of MajdataView/Assets/MaimaiColorEffect.shader (GPL-3.0).
// SwiftUI supplies premultiplied sprite color; preserve its alpha and material ramp.
[[ stitchable ]] half4 hanabi(float2 position, half4 color, float2 size, float time, float alpha) {
    float2 uv = position / size + 0.5;
    uv.y = 1.0 - uv.y;
    float2 d = uv - 0.5;
    float radius = clamp(dot(d, d) * 4, 0.0, 1.0) * alpha;
    float a = alpha * clamp((radius - 0.018) / (0.054 - 0.018), 0.0, 1.0)
        * clamp((1 - radius - (1 - 0.429)) / (0.429 - 0.36), 0.0, 1.0);
    float angle = atan2(d.y, d.x);
    if (angle < 0) angle += 6.28318;
    float hue = ceil(fmod(angle / 6.28 * 3 + ceil(time * 0.5 * 5) * 0.2, 1.0) * 5) / 5;
    float3 rgb = clamp(abs(fmod(hue * 6 + float3(0,4,2), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    rgb = rgb * rgb * (3 - 2 * rgb);
    rgb = mix(float3(1), rgb, 0.545);
    return half4(color.rgb * half3(rgb) * half(a), color.a * half(a));
}
