#version 450
#extension GL_GOOGLE_include_directive : require

layout(set = 0, binding = 0) uniform sampler2D base_color;

#include "lit.glsl"

void main() {
    vec4 texel = texture(base_color, surface_coordinate);
    if (texel.a < 0.5) {
        discard;
    }
    color = lit_color(linear_from_srgb(texel.rgb), world_normal);
}
