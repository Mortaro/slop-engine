#version 450

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 texture_coordinate;
layout(location = 3) in uvec4 joints;
layout(location = 4) in vec4 weights;

layout(push_constant) uniform Push {
    mat4 view_projection;
    uint draw;
} push;

struct Draw {
    mat4 model;
    uint palette_first;
    uint padding_one;
    uint padding_two;
    uint padding_three;
};

layout(std430, set = 1, binding = 0) readonly buffer Draws {
    Draw draws[];
};

layout(std430, set = 1, binding = 1) readonly buffer Palettes {
    mat4 palettes[];
};

layout(location = 0) out vec3 world_normal;
layout(location = 1) out vec2 surface_coordinate;
layout(location = 2) out vec3 world_position;

void main() {
    Draw draw = draws[push.draw];
    mat4 skin = palettes[draw.palette_first + joints.x] * weights.x
        + palettes[draw.palette_first + joints.y] * weights.y
        + palettes[draw.palette_first + joints.z] * weights.z
        + palettes[draw.palette_first + joints.w] * weights.w;
    mat4 world = draw.model * skin;
    vec4 placed = world * vec4(position, 1.0);
    world_normal = normalize(mat3(world) * normal);
    surface_coordinate = texture_coordinate;
    world_position = placed.xyz;
    gl_Position = push.view_projection * placed;
}
