#version 450

// Writes the terrain's height and up-facing normal, seen from straight above, for the grass scatter to stand on.

layout(location = 0) in vec3 world_normal;
layout(location = 2) in vec3 world_position;

layout(location = 0) out vec4 ground;

void main() {
    vec3 normal = normalize(world_normal);
    if (normal.y < 0.0) {
        normal = -normal;
    }
    ground = vec4(world_position.y, normal);
}
