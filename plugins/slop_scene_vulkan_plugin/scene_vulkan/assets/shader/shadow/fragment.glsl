#version 450

layout(set = 0, binding = 0) uniform sampler2D base_color;

layout(location = 0) in vec3 world_normal;
layout(location = 1) in vec2 surface_coordinate;
layout(location = 2) in vec3 world_position;
layout(location = 3) flat in uint surface_masked;

void main() {
    if (surface_masked != 0u && texture(base_color, surface_coordinate).a < 0.3333) {
        discard;
    }
}
