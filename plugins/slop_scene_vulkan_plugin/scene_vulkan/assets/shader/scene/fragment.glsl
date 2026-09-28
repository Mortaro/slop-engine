#version 450
#extension GL_GOOGLE_include_directive : require

layout(set = 0, binding = 0) uniform sampler2D base_color;

#include "lit.glsl"

void main() {
    vec4 texel = texture(base_color, surface_coordinate);
    if (surface_masked != 0u && texel.a < 0.3333) {
        discard;
    }
    color = lit_color(linear_from_srgb(texel.rgb), world_normal, lighting.material.xyz);
}
