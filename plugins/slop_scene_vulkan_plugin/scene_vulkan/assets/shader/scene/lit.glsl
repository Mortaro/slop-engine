
const float pi = 3.14159265;
const float minimum_roughness = 0.045;
const uint tiles_across = 16u;
const uint tiles_down = 9u;
const uint depth_slices = 24u;


layout(std430, set = 1, binding = 2) readonly buffer Lighting {
    vec4 sun_toward;
    vec4 sun_radiance;
    vec4 sky_radiance;
    vec4 ground_radiance;
    vec4 fog;
    vec4 eye;
    vec4 material;
    // one orthographic sun view per cascade, each drawn into a quarter of the shadow atlas
    mat4 cascade_view_projections[4];
    mat4 view;
    // near, slices per doubling of depth, and the two projection scales
    vec4 clusters;
    // each cascade's far distance from the eye, along the view
    vec4 cascade_splits;
    // each cascade's texel size in metres
    vec4 cascade_texels;
    // each cascade's depth range in metres
    vec4 cascade_depths;
    // fade start, fade end (the shadow distance), and the share of a cascade blended into the next
    vec4 shadow_fade;
} lighting;

layout(set = 1, binding = 3) uniform sampler2DShadow shadow_map;

// A point light is a spot light whose cone never cuts: cone_scale 0, cone_offset 1.
struct LocalLight {
    vec3 position;
    float range;
    vec3 toward;
    float unused_kind;
    vec3 color;
    float intensity;
    float cone_scale;
    float cone_offset;
    float unused_0;
    float unused_1;
};

struct ClusterRange {
    uint first;
    uint count;
};

layout(std430, set = 1, binding = 4) readonly buffer LocalLights {
    LocalLight local_lights[];
};

layout(std430, set = 1, binding = 5) readonly buffer Clusters {
    ClusterRange cluster_ranges[];
};

layout(std430, set = 1, binding = 6) readonly buffer LightIndices {
    uint light_indices[];
};

layout(location = 0) in vec3 world_normal;
layout(location = 1) in vec2 surface_coordinate;
layout(location = 2) in vec3 world_position;
// Unreal's masked materials clip below a third; opaque ones never clip.
layout(location = 3) flat in uint surface_masked;

layout(location = 0) out vec4 color;

vec3 linear_from_srgb(vec3 encoded) {
    vec3 low = encoded / 12.92;
    vec3 high = pow((encoded + 0.055) / 1.055, vec3(2.4));
    return mix(low, high, step(vec3(0.04045), encoded));
}

float distribution_ggx(float normal_dot_half, float alpha) {
    float alpha_squared = alpha * alpha;
    float denominator = normal_dot_half * normal_dot_half * (alpha_squared - 1.0) + 1.0;
    return alpha_squared / (pi * denominator * denominator);
}

float visibility_smith(float normal_dot_view, float normal_dot_light, float alpha) {
    float alpha_squared = alpha * alpha;
    float view_term = normal_dot_light * sqrt(normal_dot_view * normal_dot_view * (1.0 - alpha_squared) + alpha_squared);
    float light_term = normal_dot_view * sqrt(normal_dot_light * normal_dot_light * (1.0 - alpha_squared) + alpha_squared);
    return 0.5 / max(view_term + light_term, 1e-7);
}

vec3 fresnel_schlick(vec3 at_normal, float at_grazing, float view_dot_half) {
    float complement = 1.0 - view_dot_half;
    float squared = complement * complement;
    return at_normal + (vec3(at_grazing) - at_normal) * squared * squared * complement;
}

float fog_optical_depth(vec3 start, vec3 finish) {
    float density = lighting.fog.x;
    float falloff = lighting.fog.y;
    float base_height = lighting.fog.z;
    float rise = finish.y - start.y;
    float distance_travelled = length(finish - start);
    float density_at_start = density * exp(-falloff * (start.y - base_height));
    float exponent = falloff * rise;
    float shape = abs(exponent) < 1e-3 ? 1.0 - 0.5 * exponent + exponent * exponent / 6.0 : (1.0 - exp(-exponent)) / exponent;
    return density_at_start * distance_travelled * shape;
}

float cascade_visibility(int cascade, vec3 position, vec3 normal) {
    float texel = lighting.cascade_texels[cascade];
    vec3 offset_position = position + normal * texel * 1.5;
    vec4 light_clip = lighting.cascade_view_projections[cascade] * vec4(offset_position, 1.0);
    vec3 light_coordinate = light_clip.xyz / light_clip.w;
    vec2 cascade_coordinate = light_coordinate.xy * 0.5 + 0.5;
    if (cascade_coordinate.x <= 0.0 || cascade_coordinate.x >= 1.0 || cascade_coordinate.y <= 0.0 || cascade_coordinate.y >= 1.0 || light_coordinate.z >= 1.0) {
        return 1.0;
    }
    vec2 atlas_texel = 1.0 / vec2(textureSize(shadow_map, 0));
    vec2 corner = vec2(float(cascade & 1), float(cascade >> 1)) * 0.5;
    vec2 low = corner + atlas_texel * 1.5;
    vec2 high = corner + 0.5 - atlas_texel * 1.5;
    vec2 atlas_coordinate = corner + cascade_coordinate * 0.5;
    float depth_bias = texel * 1.5 / lighting.cascade_depths[cascade];
    float lit = 0.0;
    for (int row = -1; row <= 1; row++) {
        for (int column = -1; column <= 1; column++) {
            vec2 sample_at = clamp(atlas_coordinate + vec2(float(column), float(row)) * atlas_texel, low, high);
            lit += texture(shadow_map, vec3(sample_at, light_coordinate.z - depth_bias));
        }
    }
    return lit / 9.0;
}

float sun_visibility(vec3 position, vec3 normal) {
    float depth = -(lighting.view * vec4(position, 1.0)).z;
    float fade_end = lighting.shadow_fade.y;
    if (depth >= fade_end) {
        return 1.0;
    }
    int cascade = 0;
    while (cascade < 3 && depth > lighting.cascade_splits[cascade]) {
        cascade++;
    }
    float visibility = cascade_visibility(cascade, position, normal);
    float start = cascade == 0 ? 0.0 : lighting.cascade_splits[cascade - 1];
    float end = lighting.cascade_splits[cascade];
    float blend_start = end - (end - start) * lighting.shadow_fade.z;
    if (cascade < 3 && depth > blend_start) {
        float next = cascade_visibility(cascade + 1, position, normal);
        visibility = mix(visibility, next, (depth - blend_start) / (end - blend_start));
    }
    return mix(visibility, 1.0, smoothstep(lighting.shadow_fade.x, fade_end, depth));
}

struct Surface {
    vec3 normal;
    vec3 toward_eye;
    vec3 diffuse_color;
    vec3 specular_color;
    float at_grazing;
    float alpha;
};

// The light a surface sends toward the eye per unit of illuminance arriving from toward_light.
vec3 reflectance(Surface surface, vec3 toward_light) {
    float normal_dot_light = dot(surface.normal, toward_light);
    if (normal_dot_light <= 0.0) {
        return vec3(0.0);
    }
    vec3 half_vector = normalize(toward_light + surface.toward_eye);
    float normal_dot_view = clamp(dot(surface.normal, surface.toward_eye), 1e-4, 1.0);
    float normal_dot_half = clamp(dot(surface.normal, half_vector), 0.0, 1.0);
    float view_dot_half = clamp(dot(surface.toward_eye, half_vector), 0.0, 1.0);
    normal_dot_light = min(normal_dot_light, 1.0);
    vec3 reflected = distribution_ggx(normal_dot_half, surface.alpha) * visibility_smith(normal_dot_view, normal_dot_light, surface.alpha)
        * fresnel_schlick(surface.specular_color, surface.at_grazing, view_dot_half);
    return (surface.diffuse_color / pi + reflected) * normal_dot_light;
}

// Inverse square floored at 1 cm, windowed to exactly zero at the range (Karis 2013).
float windowed_inverse_square(float distance_travelled, float range) {
    float distance_squared = distance_travelled * distance_travelled;
    float ratio_squared = distance_squared / max(range * range, 1e-8);
    float window = clamp(1.0 - ratio_squared * ratio_squared, 0.0, 1.0);
    return window * window / max(distance_squared, 0.0001);
}

uint cluster_of(vec3 position) {
    vec3 seen = (lighting.view * vec4(position, 1.0)).xyz;
    float depth = max(-seen.z, 1e-4);
    float near = lighting.clusters.x;
    uint slice = 0u;
    if (depth > near) {
        slice = uint(min(floor(log2(depth / near) * lighting.clusters.y), float(depth_slices - 1u)));
    }
    float across = seen.x * lighting.clusters.z / depth * 0.5 + 0.5;
    float down = 0.5 - seen.y * lighting.clusters.w / depth * 0.5;
    uint column = uint(clamp(floor(across * float(tiles_across)), 0.0, float(tiles_across - 1u)));
    uint row = uint(clamp(floor(down * float(tiles_down)), 0.0, float(tiles_down - 1u)));
    return column + tiles_across * (row + tiles_down * slice);
}

vec3 local_radiance(Surface surface, vec3 position) {
    ClusterRange range = cluster_ranges[cluster_of(position)];
    vec3 radiance = vec3(0.0);
    for (uint index = 0u; index < range.count; index++) {
        LocalLight light = local_lights[light_indices[range.first + index]];
        vec3 to_light = light.position - position;
        float distance_travelled = length(to_light);
        vec3 toward_light = to_light / max(distance_travelled, 1e-4);
        float cone = clamp(dot(-toward_light, light.toward) * light.cone_scale + light.cone_offset, 0.0, 1.0);
        float falloff = windowed_inverse_square(distance_travelled, light.range) * cone * cone;
        radiance += reflectance(surface, toward_light) * light.color * light.intensity * falloff;
    }
    return radiance;
}

// material_terms: roughness, specular, metallic
vec4 lit_color(vec3 base, vec3 surface_normal, vec3 material_terms) {
    float roughness = material_terms.x;
    float specular = material_terms.y;
    float metallic = material_terms.z;
    vec3 normal = normalize(surface_normal);
    vec3 toward_eye = normalize(lighting.eye.xyz - world_position);
    if (dot(normal, toward_eye) < 0.0) {
        normal = -normal;
    }
    vec3 diffuse_color = base * (1.0 - metallic);
    vec3 specular_color = mix(vec3(0.08 * specular), base, metallic);
    float at_grazing = clamp(50.0 * specular_color.g, 0.0, 1.0);
    float alpha = max(roughness, minimum_roughness);
    alpha = alpha * alpha;
    Surface surface = Surface(normal, toward_eye, diffuse_color, specular_color, at_grazing, alpha);
    vec3 toward_light = normalize(lighting.sun_toward.xyz);
    vec3 radiance = vec3(0.0);
    if (dot(normal, toward_light) > 0.0) {
        radiance = reflectance(surface, toward_light) * sun_visibility(world_position, normal) * lighting.sun_radiance.rgb;
    }
    radiance += local_radiance(surface, world_position);
    float upness = normal.y * 0.5 + 0.5;
    vec3 ambient = mix(lighting.ground_radiance.rgb, lighting.sky_radiance.rgb, upness);
    radiance += (diffuse_color + specular_color * 0.25) * ambient;
    float depth = fog_optical_depth(lighting.eye.xyz, world_position);
    float transmittance = exp(-depth);
    radiance = radiance * transmittance + lighting.sky_radiance.rgb * (1.0 - transmittance);
    return vec4(min(radiance, vec3(60000.0)), 1.0);
}
