#include <metal_stdlib>
using namespace metal;

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
