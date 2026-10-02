#version 450
#extension GL_GOOGLE_include_directive : require

// One direction of one bloom stage's Gaussian blur. The vertical pass also weights the stage by its tint and adds
// the coarser stages already summed, so the finest stage ends holding the whole bloom, as Unreal's Gaussian bloom
// does.

layout(set = 0, binding = 0) uniform sampler2D source;
layout(set = 0, binding = 1) uniform sampler2D coarser;

layout(push_constant) uniform Push {
    // one texel along the blur in texture units, the kernel radius and sigma in texels
    vec4 kernel;
    // the stage's tint, 1 when the coarser stages are added
    vec4 stage;
} push;

#include "common.glsl"

layout(location = 0) out vec4 color;

void main() {
    int reach = int(ceil(push.kernel.z));
    float sigma = push.kernel.w;
    vec3 sum = textureLod(source, surface_coordinate, 0.0).rgb;
    float weight_sum = 1.0;
    // Two texels per bilinear tap, read between them at their weighted centre.
    for (int offset = 1; offset <= reach; offset += 2) {
        float first_ratio = float(offset) / sigma;
        float second_ratio = float(offset + 1) / sigma;
        float first = exp(-0.5 * first_ratio * first_ratio);
        float second = exp(-0.5 * second_ratio * second_ratio);
        float weight = first + second;
        vec2 step_offset = push.kernel.xy * ((float(offset) * first + float(offset + 1) * second) / weight);
        sum += (textureLod(source, surface_coordinate + step_offset, 0.0).rgb + textureLod(source, surface_coordinate - step_offset, 0.0).rgb) * weight;
        weight_sum += 2.0 * weight;
    }
    vec3 blurred = sum / weight_sum * push.stage.x;
    if (push.stage.y > 0.5) {
        blurred += textureLod(coarser, surface_coordinate, 0.0).rgb;
    }
    color = vec4(blurred, 1.0);
}
