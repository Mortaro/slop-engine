#version 450
#extension GL_GOOGLE_include_directive : require

// Ground-truth ambient occlusion (Jimenez, Wu, Pesce and Jarabo 2016) from the depth buffer, applied to the
// sky light only: the scene pass wrote its ambient term into its own target, and this pass takes back the share
// of it the horizon hides. Normals are rebuilt from depth. The noise turns every frame, so the temporal pass
// averages it out.

layout(set = 0, binding = 0) uniform sampler2D depth_map;
layout(set = 0, binding = 1) uniform sampler2D scene;
layout(set = 0, binding = 2) uniform sampler2D ambient;

layout(push_constant) uniform Push {
    // the projection's x scale, y scale, depth scale and depth offset (m0, m5, m10, m14)
    vec4 projection;
    // intensity, radius in metres, distance where the fade starts, fade length
    vec4 settings;
    // noise offset of this frame, render width, render height
    vec4 frame;
} push;

#include "common.glsl"

layout(location = 0) out vec4 color;

const uint slice_count = 1u;
const uint steps_per_side = 6u;
const float falloff_share = 0.615;
const float maximum_screen_fraction = 0.1;

float distance_at(vec2 coordinate) {
    float depth = textureLod(depth_map, coordinate, 0.0).r;
    return push.projection.w / (depth + push.projection.z);
}

vec3 view_position(vec2 coordinate, float distance_metres) {
    vec2 normalised = coordinate * 2.0 - 1.0;
    return vec3(normalised.x / push.projection.x, normalised.y / push.projection.y, -1.0) * distance_metres;
}

vec3 view_position_at(vec2 coordinate) {
    return view_position(coordinate, distance_at(coordinate));
}

// The flatter of the two neighbours on each axis, so an edge does not bend the normal.
vec3 view_normal(vec2 coordinate, vec3 centre, vec2 texel) {
    vec3 left = view_position_at(coordinate - vec2(texel.x, 0.0));
    vec3 right = view_position_at(coordinate + vec2(texel.x, 0.0));
    vec3 up = view_position_at(coordinate - vec2(0.0, texel.y));
    vec3 down = view_position_at(coordinate + vec2(0.0, texel.y));
    vec3 across = abs(right.z - centre.z) < abs(centre.z - left.z) ? right - centre : centre - left;
    vec3 along = abs(down.z - centre.z) < abs(centre.z - up.z) ? down - centre : centre - up;
    vec3 normal = normalize(cross(along, across));
    return dot(normal, -centre) < 0.0 ? -normal : normal;
}

float integrate_arc(float horizon_negative, float horizon_positive, float normal_angle) {
    float cosine_normal = cos(normal_angle);
    float sine_normal = sin(normal_angle);
    float negative_arc = -cos(2.0 * horizon_negative - normal_angle) + cosine_normal + 2.0 * horizon_negative * sine_normal;
    float positive_arc = -cos(2.0 * horizon_positive - normal_angle) + cosine_normal + 2.0 * horizon_positive * sine_normal;
    return 0.25 * negative_arc + 0.25 * positive_arc;
}

float horizon_cosine(vec2 coordinate, vec2 direction, float radius_texture, vec3 centre, vec3 toward_eye, float jitter, float low_cosine) {
    float radius = push.settings.y;
    float falloff_range = falloff_share * radius;
    float falloff_start = radius - falloff_range;
    float highest = low_cosine;
    for (uint step_index = 0u; step_index < steps_per_side; step_index++) {
        float along = (float(step_index) + jitter) / float(steps_per_side);
        vec2 sample_coordinate = coordinate + direction * along * radius_texture;
        vec3 delta = view_position_at(sample_coordinate) - centre;
        float distance_metres = length(delta);
        float cosine = dot(delta, toward_eye) / max(distance_metres, 1e-4);
        float weight = clamp(1.0 - (distance_metres - falloff_start) / falloff_range, 0.0, 1.0);
        highest = max(highest, mix(low_cosine, cosine, weight));
    }
    return highest;
}

float visibility_at(vec2 coordinate, vec3 centre, vec3 normal, float noise) {
    vec3 toward_eye = normalize(-centre);
    float radius_texture = min(push.settings.y * push.projection.x * 0.5 / -centre.z, maximum_screen_fraction);
    float visibility = 0.0;
    for (uint slice = 0u; slice < slice_count; slice++) {
        float angle = (float(slice) + noise) * pi / float(slice_count);
        vec2 screen_direction = vec2(cos(angle), sin(angle));
        vec2 direction_texture = screen_direction * vec2(1.0, push.frame.y / push.frame.z);
        vec3 direction = vec3(screen_direction.x, -screen_direction.y, 0.0);
        vec3 orthogonal = direction - dot(direction, toward_eye) * toward_eye;
        vec3 axis = normalize(cross(direction, toward_eye));
        vec3 projected_normal = normal - axis * dot(normal, axis);
        float projected_length = length(projected_normal);
        float sign_of_normal = dot(orthogonal, projected_normal) >= 0.0 ? 1.0 : -1.0;
        float cosine_normal = clamp(dot(projected_normal, toward_eye) / max(projected_length, 1e-4), -1.0, 1.0);
        float normal_angle = sign_of_normal * acos(cosine_normal);
        float cosine_positive = horizon_cosine(coordinate, direction_texture, radius_texture, centre, toward_eye, noise, cos(normal_angle + pi / 2.0));
        float cosine_negative = horizon_cosine(coordinate, -direction_texture, radius_texture, centre, toward_eye, noise, cos(normal_angle - pi / 2.0));
        float horizon_positive = normal_angle + clamp(acos(clamp(cosine_positive, -1.0, 1.0)) - normal_angle, -pi / 2.0, pi / 2.0);
        float horizon_negative = normal_angle + clamp(-acos(clamp(cosine_negative, -1.0, 1.0)) - normal_angle, -pi / 2.0, pi / 2.0);
        visibility += projected_length * integrate_arc(horizon_negative, horizon_positive, normal_angle);
    }
    return clamp(visibility / float(slice_count), 0.0, 1.0);
}

void main() {
    vec3 lit = textureLod(scene, surface_coordinate, 0.0).rgb;
    float intensity = push.settings.x;
    float depth = textureLod(depth_map, surface_coordinate, 0.0).r;
    if (intensity <= 0.0 || depth <= 0.0) {
        color = vec4(lit, 1.0);
        return;
    }
    vec3 centre = view_position(surface_coordinate, push.projection.w / (depth + push.projection.z));
    float fade = clamp((-centre.z - push.settings.z) / max(push.settings.w, 1e-3), 0.0, 1.0);
    intensity *= 1.0 - fade;
    if (intensity <= 0.0) {
        color = vec4(lit, 1.0);
        return;
    }
    vec2 texel = 1.0 / push.frame.yz;
    vec3 normal = view_normal(surface_coordinate, centre, texel);
    float noise = fract(gradient_noise(gl_FragCoord.xy + push.frame.x * 5.588238));
    float visibility = visibility_at(surface_coordinate, centre, normal, noise);
    float occlusion = 1.0 - intensity * (1.0 - visibility);
    vec3 sky_light = textureLod(ambient, surface_coordinate, 0.0).rgb;
    color = vec4(max(lit - sky_light * (1.0 - occlusion), vec3(0.0)), 1.0);
}
