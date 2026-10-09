#version 450
#extension GL_GOOGLE_include_directive : require

// Grass is lit, shadowed, fogged and cut out like a masked mesh with the default material (roughness 0.7,
// specular 0.5, not metallic); it has no material of its own.

layout(set = 0, binding = 0) uniform sampler2D base_color;

#include "../scene/lit.glsl"

void main() {
    vec4 texel = texture(base_color, surface_coordinate);
    if (surface_masked != 0u && texel.a < 0.3333) {
        discard;
    }
    color = lit_color(linear_from_srgb(texel.rgb), world_normal, vec3(0.7, 0.5, 0.0));
}
