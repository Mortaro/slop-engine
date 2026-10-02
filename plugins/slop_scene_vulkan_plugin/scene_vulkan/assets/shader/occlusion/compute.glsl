#version 450

// Each invocation takes the farthest (smallest, reversed-Z) depth of a 4x4 pixel square with four gathers (past
// the image's edge the sampler clamps to the edge, which only repeats real pixels); a 4x4 group of invocations
// covers one 16x16 pixel texel of the occlusion map, and its first invocation writes the texel.
layout(local_size_x = 8, local_size_y = 8) in;

layout(set = 0, binding = 0) uniform sampler2D depth_image;

layout(std430, set = 0, binding = 1) writeonly buffer Farthest {
    float farthest[];
};

layout(push_constant) uniform Push {
    uint width;
    uint height;
    uint columns;
    uint rows;
    uint block;
} push;

shared float squares[64];

void main() {
    uvec2 square = gl_GlobalInvocationID.xy;
    vec2 size = vec2(push.width, push.height);
    vec2 corner = vec2(square * 4u) + 1.0;
    vec4 first = textureGather(depth_image, corner / size);
    vec4 second = textureGather(depth_image, (corner + vec2(2.0, 0.0)) / size);
    vec4 third = textureGather(depth_image, (corner + vec2(0.0, 2.0)) / size);
    vec4 fourth = textureGather(depth_image, (corner + vec2(2.0, 2.0)) / size);
    vec4 lowest = min(min(first, second), min(third, fourth));
    float result = min(min(lowest.x, lowest.y), min(lowest.z, lowest.w));
    uvec2 local = gl_LocalInvocationID.xy;
    squares[local.y * 8u + local.x] = result;
    barrier();
    if (local.x % 4u != 0u || local.y % 4u != 0u) {
        return;
    }
    for (uint y = 0u; y < 4u; y++) {
        for (uint x = 0u; x < 4u; x++) {
            result = min(result, squares[(local.y + y) * 8u + local.x + x]);
        }
    }
    uvec2 texel = square / 4u;
    if (texel.x < push.columns && texel.y < push.rows) {
        farthest[texel.y * push.columns + texel.x] = result;
    }
}
