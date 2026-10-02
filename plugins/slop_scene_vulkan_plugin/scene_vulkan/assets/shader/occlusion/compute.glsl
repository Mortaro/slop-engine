#version 450

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

void main() {
    uvec2 texel = gl_GlobalInvocationID.xy;
    if (texel.x >= push.columns || texel.y >= push.rows) {
        return;
    }
    uint left = texel.x * push.block;
    uint top = texel.y * push.block;
    uint right = min(left + push.block, push.width);
    uint bottom = min(top + push.block, push.height);
    float result = 1.0;
    for (uint y = top; y < bottom; y++) {
        for (uint x = left; x < right; x++) {
            result = min(result, texelFetch(depth_image, ivec2(x, y), 0).r);
        }
    }
    farthest[texel.y * push.columns + texel.x] = result;
}
