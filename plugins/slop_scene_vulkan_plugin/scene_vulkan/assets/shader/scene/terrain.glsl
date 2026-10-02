#version 450
#extension GL_GOOGLE_include_directive : require

// A port of a splat-index Unreal terrain material, formula for formula (docs/scene.md#terrain).

layout(set = 0, binding = 0) uniform sampler2DArray layer_colors;
layout(set = 0, binding = 1) uniform sampler2DArray layer_normals;
layout(set = 0, binding = 2) uniform sampler2DArray detail_map;
layout(set = 0, binding = 3) uniform sampler2DArray far_color_map;
layout(set = 0, binding = 4) uniform sampler2DArray grass_overlay;
layout(set = 0, binding = 5) uniform sampler2D control_low;
layout(set = 0, binding = 6) uniform sampler2D control_high;
layout(set = 0, binding = 7) uniform sampler2D scale_low;
layout(set = 0, binding = 8) uniform sampler2D scale_high;
layout(set = 0, binding = 9) uniform sampler2D splat_low;
layout(set = 0, binding = 10) uniform sampler2D splat_high;
layout(set = 0, binding = 11) uniform sampler2D grass_mask;

layout(std430, set = 0, binding = 12) readonly buffer TerrainParameters {
    // tiles across, tiles down, layer tiles per metre for a scale texel of 1, layer count
    vec4 tiling;
    // control width and depth in metres, roughness, specular
    vec4 control;
    // detail tiles per metre, strength, fade depth in metres
    vec4 detail;
    // overlay tiles per metre, overlay brightness, mask strength, whether there is a mask
    vec4 grass;
    // slope smoothstep low and high (world up of the normal), far colour fade start and end
    vec4 slope;
} terrain;

#include "lit.glsl"

void main() {
    vec2 ground = world_position.xz;
    vec2 control_uv = ground / terrain.control.xy;
    ivec2 tiles = ivec2(terrain.tiling.xy);
    ivec2 tile = clamp(ivec2(floor(control_uv * terrain.tiling.xy)), ivec2(0), tiles - 1);
    vec4 picks_low = texelFetch(control_low, tile, 0) * 255.0;
    vec4 picks_high = texelFetch(control_high, tile, 0) * 255.0;
    vec4 scales_low = texture(scale_low, control_uv) * terrain.tiling.z;
    vec4 scales_high = texture(scale_high, control_uv) * terrain.tiling.z;
    vec4 paint_low = texture(splat_low, control_uv);
    vec4 paint_high = texture(splat_high, control_uv);
    float picks[8] = float[8](picks_low.r, picks_low.g, picks_low.b, picks_low.a, picks_high.r, picks_high.g, picks_high.b, picks_high.a);
    float scales[8] = float[8](scales_low.r, scales_low.g, scales_low.b, scales_low.a, scales_high.r, scales_high.g, scales_high.b, scales_high.a);
    float weights[8] = float[8](1.0, paint_low.r, paint_low.g, paint_low.b, paint_low.a, paint_high.r, paint_high.g, paint_high.b);
    float last_layer = terrain.tiling.w - 1.0;
    vec3 albedo = vec3(0.0);
    vec3 bumped = vec3(0.0, 0.0, 1.0);
    for (int slot = 0; slot < 8; slot++) {
        float weight = weights[slot];
        if (slot > 0 && weight < 0.002) {
            continue;
        }
        vec3 coordinate = vec3(ground * scales[slot], clamp(floor(picks[slot] + 0.5), 0.0, last_layer));
        albedo = mix(albedo, texture(layer_colors, coordinate).rgb, weight);
        vec2 slope = texture(layer_normals, coordinate).xy * 2.0 - 1.0;
        vec3 layer_normal = vec3(slope, sqrt(max(1.0 - dot(slope, slope), 0.0)));
        bumped = mix(bumped, layer_normal, weight);
    }
    float depth = max(-(lighting.view * vec4(world_position, 1.0)).z, 0.0);
    float detail_fade = clamp(1.0 - depth / terrain.detail.z, 0.0, 1.0);
    float detail_value = texture(detail_map, vec3(ground * terrain.detail.x, 0.0)).r;
    albedo *= 1.0 + (detail_value - 0.5) * terrain.detail.y * detail_fade;
    vec3 up = normalize(world_normal);
    if (terrain.grass.w > 0.5) {
        vec3 overlay = texture(grass_overlay, vec3(ground * terrain.grass.x, 0.0)).rgb * dot(albedo, vec3(0.3, 0.59, 0.11)) * terrain.grass.y;
        float slope = clamp((up.y - terrain.slope.x) / (terrain.slope.y - terrain.slope.x), 0.0, 1.0);
        float smooth_slope = slope * slope * (3.0 - 2.0 * slope);
        float amount = clamp(texture(grass_mask, control_uv).r * terrain.grass.z * smooth_slope, 0.0, 1.0);
        albedo = mix(albedo, overlay, amount);
    }
    float distance_to_eye = length(lighting.eye.xyz - world_position);
    float far_mix = smoothstep(terrain.slope.z, terrain.slope.w, distance_to_eye);
    albedo = mix(albedo, texture(far_color_map, vec3(surface_coordinate, 0.0)).rgb, far_mix);
    bumped = mix(bumped, vec3(0.0, 0.0, 1.0), far_mix);
    vec3 along_x = normalize(vec3(1.0, 0.0, 0.0) - up * up.x);
    vec3 along_z = normalize(cross(along_x, up));
    along_z = along_z * sign(dot(along_z, vec3(0.0, 0.0, 1.0)) + 1e-6);
    vec3 surface = normalize(along_x * bumped.x + along_z * bumped.y + up * max(bumped.z, 1e-3));
    color = lit_color(albedo, surface, vec3(terrain.control.z, terrain.control.w, 0.0));
}
