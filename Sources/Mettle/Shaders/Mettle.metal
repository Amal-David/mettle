#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 transform;
    float4 viewportAndSize;
    float4 color;
    float4 gradientRow0;
    float4 gradientRow1;
    float4 paintInfo; // kind, stopCount, paintOpacity, unused
};
struct Stop { float4 color; float4 info; };
struct VertexOut { float4 position [[position]]; float2 uv; };

vertex VertexOut fm_vertex(uint index [[vertex_id]],
                          const device float2 *vertices [[buffer(0)]],
                          constant Uniforms &u [[buffer(1)]]) {
    float2 p = vertices[index];
    float4 world = u.transform * float4(p, 0, 1);
    VertexOut out;
    out.position = float4(world.x * 2 / u.viewportAndSize.x - 1,
                         1 - world.y * 2 / u.viewportAndSize.y, 0, 1);
    out.uv = p / max(u.viewportAndSize.zw, float2(0.00001));
    return out;
}

fragment float4 fm_fragment(VertexOut in [[stage_in]],
                           constant Uniforms &u [[buffer(0)]],
                           constant Stop *stops [[buffer(1)]]) {
    float4 color = u.color;
    int kind = int(u.paintInfo.x);
    if (kind != 0) {
        float3 uv = float3(in.uv, 1);
        float2 g = float2(dot(u.gradientRow0.xyz, uv), dot(u.gradientRow1.xyz, uv));
        float t = kind == 1 ? g.x : 2 * length(g - float2(0.5));
        uint n = uint(u.paintInfo.y);
        color = stops[0].color;
        for (uint i = 1; i < n; ++i) {
            float a = stops[i-1].info.x, b = stops[i].info.x;
            if (t >= b) { color = stops[i].color; continue; }
            float f = b > a ? clamp((t-a)/(b-a), 0.0f, 1.0f) : 0.0f;
            color = mix(stops[i-1].color, stops[i].color, f);
            break;
        }
    }
    float alpha = clamp(color.a * u.paintInfo.z, 0.0f, 1.0f);
    return float4(color.rgb * alpha, alpha); // Premultiplied throughout the render graph.
}

vertex VertexOut fm_fullscreen(uint index [[vertex_id]]) {
    const float2 positions[3] = { float2(-1,1), float2(-1,-3), float2(3,1) };
    VertexOut out;
    out.position = float4(positions[index],0,1);
    out.uv = float2(0);
    return out;
}
fragment float4 fm_composite(VertexOut in [[stage_in]],
                            texture2d<float> source [[texture(0)]],
                            texture2d<float> mask [[texture(1)]],
                            constant float4 &options [[buffer(0)]]) {
    uint2 p = uint2(in.position.xy);
    float coverage = options.y > 0.5 ? mask.read(p).a : 1.0;
    return source.read(p) * (coverage * options.x);
}
