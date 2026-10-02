#version 450
#extension GL_GOOGLE_include_directive : require

layout(set = 0, binding = 0) uniform sampler2D base_color;
layout(set = 0, binding = 5) uniform sampler2D opacity_map;

#include "../scene/material.glsl"

layout(location = 0) in vec3 world_normal;
layout(location = 1) in vec2 surface_coordinate;
layout(location = 2) in vec3 world_position;
layout(location = 3) flat in uint surface_masked;
layout(location = 4) flat in float surface_fade;

void main() {
    if (surface_masked != 0u) {
        vec2 coordinate = material_coordinate(surface_coordinate);
        vec4 texel = texture(base_color, coordinate);
        if (material_opacity(opacity_map, texel, coordinate) < 0.3333) {
            discard;
        }
    }
    dither_fade(surface_fade);
}
