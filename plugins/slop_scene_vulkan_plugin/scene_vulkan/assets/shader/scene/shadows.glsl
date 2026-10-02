// Shadows from one depth atlas (docs/scene.md#shadows): the sun's cascades fill the left half in a 2x2 grid, and
// point and spot lights fill tiles of the right half. Included by lit.glsl after the Lighting buffer.

// A point light's six faces, in tile order: the axis each face looks along and its up.
const vec3 face_forward[6] = vec3[6](vec3(1.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0));
const vec3 face_up[6] = vec3[6](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));

// Normal offset and depth bias, in texels of the map being read.
const float sun_normal_offset = 1.0;
const float sun_depth_bias = 1.0;
const float local_normal_offset = 1.0;
const float local_depth_bias = 1.0;

float shadow_tap(vec2 at, vec2 low, vec2 high, vec2 inverse_size, float depth) {
    return texture(shadow_map, vec3(clamp(at, low, high) * inverse_size, depth));
}

// Castano's optimized PCF: a 5x5 tent filter from 9 bilinear comparisons. at is in atlas texels, and low/high keep
// every tap inside one tile.
float filtered_shadow(vec2 at, float depth, vec2 low, vec2 high) {
    vec2 inverse_size = 1.0 / vec2(textureSize(shadow_map, 0));
    vec2 base = floor(at + 0.5);
    vec2 fraction = at + 0.5 - base;
    base -= 0.5;
    vec3 across_weight = vec3(4.0 - 3.0 * fraction.x, 7.0, 1.0 + 3.0 * fraction.x);
    vec3 across_offset = vec3((3.0 - 2.0 * fraction.x) / across_weight.x - 2.0, (3.0 + fraction.x) / 7.0, fraction.x / across_weight.z + 2.0);
    vec3 down_weight = vec3(4.0 - 3.0 * fraction.y, 7.0, 1.0 + 3.0 * fraction.y);
    vec3 down_offset = vec3((3.0 - 2.0 * fraction.y) / down_weight.x - 2.0, (3.0 + fraction.y) / 7.0, fraction.y / down_weight.z + 2.0);
    float sum = 0.0;
    for (int row = 0; row < 3; row++) {
        for (int column = 0; column < 3; column++) {
            vec2 offset = vec2(across_offset[column], down_offset[row]);
            sum += across_weight[column] * down_weight[row] * shadow_tap(base + offset, low, high, inverse_size, depth);
        }
    }
    return sum / 144.0;
}

float cascade_visibility(int cascade, vec3 position, vec3 normal) {
    float texel = lighting.cascade_texels[cascade];
    vec3 offset_position = position + normal * texel * sun_normal_offset;
    vec4 light_clip = lighting.cascade_view_projections[cascade] * vec4(offset_position, 1.0);
    vec2 cascade_coordinate = light_clip.xy * 0.5 + 0.5;
    if (any(lessThan(cascade_coordinate, vec2(0.0))) || any(greaterThan(cascade_coordinate, vec2(1.0))) || light_clip.z >= 1.0) {
        return 1.0;
    }
    float size = lighting.shadow_atlas.z;
    vec2 corner = vec2(float(cascade & 1), float(cascade >> 1)) * size;
    float depth = light_clip.z - texel * sun_depth_bias / lighting.cascade_depths[cascade];
    return filtered_shadow(corner + cascade_coordinate * size, depth, corner + 1.0, corner + size - 1.0);
}

// The sun's shadow: the cascade whose split holds the depth, blended from the previous cascade over the transition
// just past each split, and faded out toward the shadow distance.
float sun_visibility(vec3 position, vec3 normal) {
    int count = int(lighting.shadow_fade.z);
    float depth = -(lighting.view * vec4(position, 1.0)).z;
    if (count == 0 || depth >= lighting.shadow_fade.y) {
        return 1.0;
    }
    int cascade = 0;
    while (cascade < count - 1 && depth > lighting.cascade_splits[cascade]) {
        cascade++;
    }
    float visibility = cascade_visibility(cascade, position, normal);
    if (cascade > 0) {
        float split = lighting.cascade_splits[cascade - 1];
        float previous_start = cascade > 1 ? lighting.cascade_splits[cascade - 2] : 0.0;
        float extension = (split - previous_start) * lighting.shadow_fade.w;
        if (depth < split + extension) {
            float previous = cascade_visibility(cascade - 1, position, normal);
            visibility = mix(previous, visibility, (depth - split) / extension);
        }
    }
    float fade = clamp((depth - lighting.shadow_fade.x) / max(lighting.shadow_fade.y - lighting.shadow_fade.x, 1e-4), 0.0, 1.0);
    return mix(visibility, 1.0, fade);
}

// A point or spot light's shadow from its tiles: one for a spot, six cube faces for a point light.
float local_visibility(uint index, vec3 position, vec3 normal) {
    LocalShadow shadow = lighting.local_shadows[index];
    vec3 light_position = shadow.position.xyz;
    float focal = shadow.view.y;
    float near = shadow.view.z;
    float far = shadow.view.w;
    float tile = lighting.shadow_atlas.w;
    float texel = 2.0 * length(position - light_position) / (focal * tile);
    vec3 offset_position = position + normal * texel * local_normal_offset;
    vec3 seen;
    uint face = 0u;
    if (shadow.position.w > 0.5) {
        vec3 along = offset_position - light_position;
        vec3 size = abs(along);
        if (size.x >= size.y && size.x >= size.z) {
            face = along.x > 0.0 ? 0u : 1u;
        } else if (size.y >= size.z) {
            face = along.y > 0.0 ? 2u : 3u;
        } else {
            face = along.z > 0.0 ? 4u : 5u;
        }
        vec3 forward = face_forward[face];
        vec3 up = face_up[face];
        seen = vec3(dot(along, cross(forward, up)), dot(along, up), dot(along, forward));
    } else {
        seen = (shadow.basis * vec4(offset_position, 1.0)).xyz;
    }
    if (seen.z <= near) {
        return 1.0;
    }
    vec2 projected = vec2(seen.x, -seen.y) * focal / seen.z;
    float compared = max(seen.z - texel * local_depth_bias, near);
    float depth = far * (compared - near) / ((far - near) * compared);
    uint tile_index = uint(shadow.view.x) + face;
    uint tiles_in_row = uint(lighting.shadow_atlas.y);
    vec2 corner = vec2(lighting.shadow_atlas.x + float(tile_index % tiles_in_row) * tile, float(tile_index / tiles_in_row) * tile);
    vec2 at = corner + (projected * 0.5 + 0.5) * tile;
    return filtered_shadow(at, depth, corner + 1.0, corner + tile - 1.0);
}
