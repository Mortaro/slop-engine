#version 450

// The luminance histogram automatic exposure reads: 64 bins spread evenly in EV100 over the histogram's range,
// filled from a half-size grid of the resolved frame (each sample a bilinear average of four pixels).

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0) uniform sampler2D scene;

layout(std430, set = 0, binding = 7) buffer Histogram {
    uint bins[64];
} histogram;

layout(push_constant) uniform Push {
    // lowest and highest EV100 of the histogram, one over this frame's pre-exposure
    vec4 range;
    // sample grid width and height
    vec4 grid;
} push;

shared uint local_bins[64];

void main() {
    uint index = gl_LocalInvocationIndex;
    if (index < 64u) {
        local_bins[index] = 0u;
    }
    barrier();
    uvec2 at = gl_GlobalInvocationID.xy;
    if (at.x < uint(push.grid.x) && at.y < uint(push.grid.y)) {
        vec2 coordinate = (vec2(at) + 0.5) / push.grid.xy;
        vec3 radiance = textureLod(scene, coordinate, 0.0).rgb * push.range.z;
        float luminance = dot(radiance, vec3(0.2126, 0.7152, 0.0722));
        float exposure_value = log2(max(luminance, 1e-10) * 100.0 / 12.5);
        float fraction = clamp((exposure_value - push.range.x) / (push.range.y - push.range.x), 0.0, 1.0);
        atomicAdd(local_bins[min(uint(fraction * 64.0), 63u)], 1u);
    }
    barrier();
    if (index < 64u && local_bins[index] > 0u) {
        atomicAdd(histogram.bins[index], local_bins[index]);
    }
}
