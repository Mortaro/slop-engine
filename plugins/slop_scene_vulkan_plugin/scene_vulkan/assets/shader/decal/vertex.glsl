#version 450

layout(push_constant) uniform Push {
    mat4 view_projection;
    mat4 inverse_view_projection;
} push;

struct Decal {
    mat4 model;
    mat4 inverse;
    // tint and opacity
    vec4 tint;
    // emissive luminance in nits, 1 when unlit
    vec4 shading;
};

layout(std430, set = 0, binding = 1) readonly buffer Decals {
    Decal decals[];
};

layout(location = 0) out vec3 world_normal;
layout(location = 1) out vec2 surface_coordinate;
layout(location = 2) out vec3 world_position;
layout(location = 3) flat out uint surface_masked;
layout(location = 4) flat out uint decal_index;

// The unit box's corners are x + 2y + 4z; each face is wound counter-clockwise seen from outside.
const int faces[36] = int[](0, 4, 6, 0, 6, 2, 1, 3, 7, 1, 7, 5, 0, 1, 5, 0, 5, 4, 2, 6, 7, 2, 7, 3, 0, 2, 3, 0, 3, 1, 4, 5, 7, 4, 7, 6);

void main() {
    Decal decal = decals[gl_InstanceIndex];
    int corner = faces[gl_VertexIndex];
    vec3 local = vec3(float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1)) - 0.5;
    vec4 placed = decal.model * vec4(local, 1.0);
    world_normal = vec3(0.0, 1.0, 0.0);
    surface_coordinate = vec2(0.0);
    world_position = placed.xyz;
    surface_masked = 0u;
    decal_index = uint(gl_InstanceIndex);
    gl_Position = push.view_projection * placed;
}
