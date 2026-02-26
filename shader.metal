#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexMain(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2(-1.0,  1.0), float2( 1.0,  1.0)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID];
    
    // Fix aspect ratio by passing it from host, or just keep it square for simplicity.
    // Assuming UI is drawn in a square frame or we just draw in normalized coordinates.
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]], 
                             constant float &progress [[buffer(0)]], 
                             constant float3 &color [[buffer(1)]],
                             constant float &aspectRatio [[buffer(2)]]) {
    float2 uv = in.uv;
    uv.x *= aspectRatio;
    
    float dist = length(uv);
    
    // Base background
    float4 bgColor = float4(0.1, 0.1, 0.12, 1.0);
    
    // Check if within outer radius and outside inner radius
    float outerRad = 0.8;
    float innerRad = 0.65;
        
    if (dist < outerRad && dist > innerRad) {
        // Calculate angle from straight up (12 o'clock)
        // atan2(y,x) gives angle from x-axis. We want from y-axis.
        float angle = atan2(uv.x, uv.y); 
        if (angle < 0.0) {
            angle += 2.0 * 3.14159265359;
        }
        
        float normalizedAngle = angle / (2.0 * 3.14159265359);
        
        // Anti-aliasing edges
        float edge = smoothstep(outerRad, outerRad - 0.01, dist) * smoothstep(innerRad, innerRad + 0.01, dist);
        
        if (normalizedAngle <= progress) {
            return mix(bgColor, float4(color, 1.0), edge);
        } else {
            return mix(bgColor, float4(0.2, 0.2, 0.2, 1.0), edge); // Empty track
        }
    } else if (dist <= innerRad) {
        // Center of the pomodoro could be a soft pulse or just dark
        return float4(bgColor.rgb * 0.8, 1.0);
    }
    
    return bgColor;
}
