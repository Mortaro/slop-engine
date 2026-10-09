
// A section's material, pushed per draw run after the vertex stage's view projection and draw index.
layout(push_constant) uniform MaterialPush {
    layout(offset = 68) uint flags;
    layout(offset = 72) float normal_strength;
    // Opacity, with this frame's pulse already applied.
    layout(offset = 76) float opacity;
    // Base colour factor and roughness.
    layout(offset = 80) vec4 base_roughness;
    // Emissive luminance in nits and metallic.
    layout(offset = 96) vec4 emissive_metallic;
    // This frame's texture coordinate scroll and the specular level.
    layout(offset = 112) vec4 scroll_specular;
} material;

const uint has_normal_map = 1u;
const uint has_roughness_map = 2u;
const uint has_metallic_map = 4u;
const uint has_emissive_map = 8u;
const uint has_opacity_map = 16u;
const uint opacity_from_base = 32u;
const uint unlit_material = 64u;
const uint translucent_material = 128u;

float channel_of(vec4 texel, uint shift) {
    return texel[(material.flags >> shift) & 3u];
}

vec2 material_coordinate(vec2 coordinate) {
    return coordinate + material.scroll_specular.xy;
}

float base_opacity(vec4 base_texel) {
    float opacity = material.opacity;
    if ((material.flags & opacity_from_base) != 0u) {
        opacity *= channel_of(base_texel, 12u);
    }
    return opacity;
}

float material_opacity(sampler2D opacity_map, vec4 base_texel, vec2 coordinate) {
    if ((material.flags & has_opacity_map) != 0u) {
        return material.opacity * channel_of(texture(opacity_map, coordinate), 12u);
    }
    return base_opacity(base_texel);
}

// Unreal's screen-door fade: a 4x4 ordered (Bayer) dither keeps a pixel when its threshold is under the opacity.
void dither_fade(float fade) {
    if (fade >= 1.0) {
        return;
    }
    uvec2 cell = uvec2(gl_FragCoord.xy) & 3u;
    uint crossed = cell.x ^ cell.y;
    uint rank = ((crossed & 1u) << 3) | ((cell.y & 1u) << 2) | (crossed & 2u) | ((cell.y >> 1) & 1u);
    if (fade <= (float(rank) + 0.5) / 16.0) {
        discard;
    }
}
