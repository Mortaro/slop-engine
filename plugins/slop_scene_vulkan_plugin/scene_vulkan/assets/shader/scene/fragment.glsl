#version 450

const float pi = 3.14159265;
const float minimum_roughness = 0.045;

layout(set = 0, binding = 0) uniform sampler2D base_color;

layout(std430, set = 1, binding = 2) readonly buffer Lighting {
    vec4 sun_toward;
    vec4 sun_radiance;
    vec4 sky_radiance;
    vec4 ground_radiance;
    vec4 fog;
    vec4 eye;
    vec4 material;
    mat4 light_view_projection;
} lighting;

layout(set = 1, binding = 3) uniform sampler2DShadow shadow_map;

layout(location = 0) in vec3 world_normal;
layout(location = 1) in vec2 surface_coordinate;
layout(location = 2) in vec3 world_position;

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

float sun_visibility(vec3 position, vec3 normal) {
    vec3 offset_position = position + normal * 0.02;
    vec4 light_clip = lighting.light_view_projection * vec4(offset_position, 1.0);
    vec3 light_coordinate = light_clip.xyz / light_clip.w;
    vec2 texel_coordinate = light_coordinate.xy * 0.5 + 0.5;
    if (texel_coordinate.x <= 0.0 || texel_coordinate.x >= 1.0 || texel_coordinate.y <= 0.0 || texel_coordinate.y >= 1.0 || light_coordinate.z >= 1.0) {
        return 1.0;
    }
    vec2 texel_size = 1.0 / vec2(textureSize(shadow_map, 0));
    float lit = 0.0;
    for (int row = -1; row <= 1; row++) {
        for (int column = -1; column <= 1; column++) {
            vec2 step_offset = vec2(float(column), float(row)) * texel_size;
            lit += texture(shadow_map, vec3(texel_coordinate + step_offset, light_coordinate.z - 0.0015));
        }
    }
    return lit / 9.0;
}

void main() {
    vec4 texel = texture(base_color, surface_coordinate);
    if (texel.a < 0.5) {
        discard;
    }
    vec3 base = linear_from_srgb(texel.rgb);
    float roughness = lighting.material.x;
    float specular = lighting.material.y;
    float metallic = lighting.material.z;
    vec3 normal = normalize(world_normal);
    vec3 toward_eye = normalize(lighting.eye.xyz - world_position);
    if (dot(normal, toward_eye) < 0.0) {
        normal = -normal;
    }
    vec3 diffuse_color = base * (1.0 - metallic);
    vec3 specular_color = mix(vec3(0.08 * specular), base, metallic);
    float at_grazing = clamp(50.0 * specular_color.g, 0.0, 1.0);
    float alpha = max(roughness, minimum_roughness);
    alpha = alpha * alpha;
    vec3 toward_light = normalize(lighting.sun_toward.xyz);
    vec3 radiance = vec3(0.0);
    float normal_dot_light = dot(normal, toward_light);
    if (normal_dot_light > 0.0) {
        vec3 half_vector = normalize(toward_light + toward_eye);
        float normal_dot_view = clamp(dot(normal, toward_eye), 1e-4, 1.0);
        float normal_dot_half = clamp(dot(normal, half_vector), 0.0, 1.0);
        float view_dot_half = clamp(dot(toward_eye, half_vector), 0.0, 1.0);
        normal_dot_light = min(normal_dot_light, 1.0);
        vec3 reflected = distribution_ggx(normal_dot_half, alpha) * visibility_smith(normal_dot_view, normal_dot_light, alpha)
            * fresnel_schlick(specular_color, at_grazing, view_dot_half);
        float visibility = sun_visibility(world_position, normal);
        radiance = (diffuse_color / pi + reflected) * normal_dot_light * visibility * lighting.sun_radiance.rgb;
    }
    float upness = normal.y * 0.5 + 0.5;
    vec3 ambient = mix(lighting.ground_radiance.rgb, lighting.sky_radiance.rgb, upness);
    radiance += (diffuse_color + specular_color * 0.25) * ambient;
    float depth = fog_optical_depth(lighting.eye.xyz, world_position);
    float transmittance = exp(-depth);
    radiance = radiance * transmittance + lighting.sky_radiance.rgb * (1.0 - transmittance);
    color = vec4(min(radiance, vec3(60000.0)), 1.0);
}
