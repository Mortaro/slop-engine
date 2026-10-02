#version 450
#extension GL_GOOGLE_include_directive : require

// Draws one grass type's instances, placed by the scatter pass, through the scene's fragment shader, so grass is lit,
// shadowed, fogged and cut out like any masked mesh; the higher a vertex, the further the wind sways it.

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 texture_coordinate;
layout(location = 3) in uvec4 joints;
layout(location = 4) in vec4 weights;

#include "kinds.glsl"

layout(push_constant) uniform Push {
    mat4 view_projection;
    uint kind;
    uint masked;
} push;

layout(std430, set = 2, binding = 0) readonly buffer Kinds {
    GrassKind kinds[];
};

layout(std430, set = 2, binding = 1) readonly buffer Instances {
    vec4 instances[];
};

layout(std430, set = 2, binding = 2) readonly buffer Frame {
    GrassFrame frame;
};

layout(location = 0) out vec3 world_normal;
layout(location = 1) out vec2 surface_coordinate;
layout(location = 2) out vec3 world_position;
layout(location = 3) flat out uint surface_masked;

vec3 rotated(vec4 turn, vec3 vector) {
    vec3 twice = 2.0 * cross(turn.xyz, vector);
    return vector + turn.w * twice + cross(turn.xyz, twice);
}

void main() {
    GrassKind kind = kinds[push.kind];
    uint at = (kind.placement_output.x + uint(gl_InstanceIndex)) * 2u;
    vec4 placed = instances[at];
    vec4 turn = instances[at + 1u];
    vec3 world = rotated(turn, position * placed.w) + placed.xyz;
    float rise = max(position.y, 0.0) * placed.w;
    float phase = frame.eye.w * kind.wind.y * 6.2831853 + dot(placed.xz, vec2(0.37, 0.23));
    float gust = sin(phase) * 0.7 + sin(phase * 2.3 + 1.7) * 0.3;
    world.xz += vec2(0.8, 0.6) * kind.wind.x * rise * (gust * 0.5 + 0.5);
    world_normal = normalize(rotated(turn, normal));
    surface_coordinate = texture_coordinate;
    world_position = world;
    surface_masked = push.masked;
    gl_Position = push.view_projection * vec4(world, 1.0);
}
