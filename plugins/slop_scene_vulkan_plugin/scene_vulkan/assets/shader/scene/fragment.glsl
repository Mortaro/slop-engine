#version 450
#extension GL_GOOGLE_include_directive : require

layout(set = 0, binding = 0) uniform sampler2D base_color;
layout(set = 0, binding = 1) uniform sampler2D normal_map;
layout(set = 0, binding = 2) uniform sampler2D roughness_map;
layout(set = 0, binding = 3) uniform sampler2D metallic_map;
layout(set = 0, binding = 4) uniform sampler2D emissive_map;
layout(set = 0, binding = 5) uniform sampler2D opacity_map;

// The lean variant leaves out every map but the base colour and the unlit path, so a plain material keeps the
// registers (and the speed) of a one-texture shader.
layout(constant_id = 0) const bool full_material = true;

#include "lit.glsl"
#include "material.glsl"

layout(location = 4) flat in float surface_fade;
layout(location = 5) in vec4 world_tangent;

// Blender's tangent-space normal map: the bitangent is the tangent's sign times N x T, and the strength mixes
// the mapped normal with the surface's.
vec3 mapped_normal(vec3 normal, vec2 coordinate) {
    if ((material.flags & has_normal_map) == 0u) {
        return normal;
    }
    vec3 tangent = world_tangent.xyz - normal * dot(world_tangent.xyz, normal);
    if (dot(tangent, tangent) < 1e-10) {
        return normal;
    }
    tangent = normalize(tangent);
    vec3 bitangent = cross(normal, tangent) * world_tangent.w;
    vec3 texel = texture(normal_map, coordinate).xyz * 2.0 - 1.0;
    vec3 mapped = normalize(tangent * texel.x + bitangent * texel.y + normal * texel.z);
    return normalize(mix(normal, mapped, max(material.normal_strength, 0.0)));
}

void main() {
    vec2 coordinate = material_coordinate(surface_coordinate);
    vec4 texel = texture(base_color, coordinate);
    bool translucent = (material.flags & translucent_material) != 0u;
    float opacity = 1.0;
    if (surface_masked != 0u || translucent) {
        if (full_material) {
            opacity = material_opacity(opacity_map, texel, coordinate);
        } else {
            opacity = base_opacity(texel);
        }
        if (surface_masked != 0u && opacity < 0.3333) {
            discard;
        }
    }
    dither_fade(surface_fade);
    vec3 base = linear_from_srgb(texel.rgb) * material.base_roughness.rgb;
    vec3 emitted = material.emissive_metallic.rgb;
    if (full_material && (material.flags & has_emissive_map) != 0u) {
        emitted *= linear_from_srgb(texture(emissive_map, coordinate).rgb);
    }
    float exposure = lighting.material.w;
    float coverage = translucent ? clamp(opacity, 0.0, 1.0) : 1.0;
    if (full_material && (material.flags & unlit_material) != 0u) {
        color = finished(base * emitted * exposure, world_position, coverage);
        return;
    }
    vec3 normal = facing_normal(world_normal, world_position);
    float roughness = material.base_roughness.a;
    float metallic = material.emissive_metallic.a;
    if (full_material) {
        normal = mapped_normal(normal, coordinate);
        if ((material.flags & has_roughness_map) != 0u) {
            roughness = channel_of(texture(roughness_map, coordinate), 8u);
        }
        if ((material.flags & has_metallic_map) != 0u) {
            metallic = channel_of(texture(metallic_map, coordinate), 10u);
        }
    }
    vec3 terms = vec3(roughness, material.scroll_specular.z, metallic);
    vec3 radiance = lit_radiance(base, normal, terms, world_position) + emitted * exposure;
    color = finished(radiance, world_position, coverage);
}
