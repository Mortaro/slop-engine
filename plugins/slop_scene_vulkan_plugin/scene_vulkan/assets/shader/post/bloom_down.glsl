#version 450
#extension GL_GOOGLE_include_directive : require

// One step of the bloom's downsample chain: a 4 by 4 box from four bilinear taps. On the first step a positive
// threshold keeps only what is brighter than it, after exposure, as Unreal's bloom threshold does.

layout(set = 0, binding = 0) uniform sampler2D source;

layout(push_constant) uniform Push {
    // the source's texel size, the threshold (or below 0 for none), the exposure scale of the frame
    vec4 step_size;
} push;

#include "common.glsl"

layout(location = 0) out vec4 color;

void main() {
    vec2 texel = push.step_size.xy;
    vec3 sum = textureLod(source, surface_coordinate + texel * vec2(-1.0, -1.0), 0.0).rgb;
    sum += textureLod(source, surface_coordinate + texel * vec2(1.0, -1.0), 0.0).rgb;
    sum += textureLod(source, surface_coordinate + texel * vec2(-1.0, 1.0), 0.0).rgb;
    sum += textureLod(source, surface_coordinate + texel * vec2(1.0, 1.0), 0.0).rgb;
    vec3 average = sum * 0.25;
    float threshold = push.step_size.z;
    if (threshold > 0.0) {
        float exposed = luminance_of(average) * push.step_size.w;
        average *= max(exposed - threshold, 0.0) / max(exposed, 1e-6);
    }
    color = vec4(average, 1.0);
}
