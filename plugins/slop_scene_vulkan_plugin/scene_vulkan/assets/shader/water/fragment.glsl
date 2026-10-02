#version 450
#extension GL_GOOGLE_include_directive : require

// A water surface over the finished opaque scene: what lies under it is seen through the water column, absorbed and
// scattered per colour by its thickness (read from the scene depth), bent a little by the waves; the sky and the sun
// are reflected by Fresnel.

layout(set = 0, binding = 0) uniform sampler2D scene_color;
layout(set = 0, binding = 1) uniform sampler2D scene_depth;

#include "waves.glsl"
#include "../scene/lit.glsl"

vec3 point_behind(vec2 screen_coordinate, float depth) {
    vec4 clip = vec4(screen_coordinate * 2.0 - 1.0, depth, 1.0);
    vec4 placed = water.inverse_view_projection * clip;
    return placed.xyz / placed.w;
}

float thickness_at(vec2 screen_coordinate) {
    float depth = texture(scene_depth, screen_coordinate).r;
    if (depth <= 0.0) {
        return 100000.0;
    }
    return distance(point_behind(screen_coordinate, depth), world_position);
}

void main() {
    WaterBody body = water.bodies[push.body];
    vec3 eye = lighting.eye.xyz;
    vec3 toward_eye = normalize(eye - world_position);
    float distance_to_eye = distance(eye, world_position);
    vec3 displaced;
    vec3 normal;
    gerstner(body, surface_coordinate, distance_to_eye, displaced, normal);
    if (dot(normal, toward_eye) < 0.0) {
        normal = normalize(normal - toward_eye * dot(normal, toward_eye) * 1.01);
    }
    vec2 screen_coordinate = gl_FragCoord.xy * water.screen.zw;
    float straight_thickness = thickness_at(screen_coordinate);
    vec2 bent = screen_coordinate + normal.xz * 0.04 * clamp(straight_thickness * 0.5, 0.0, 1.0);
    float thickness = thickness_at(bent);
    if (texture(scene_depth, bent).r > gl_FragCoord.z) {
        bent = screen_coordinate;
        thickness = straight_thickness;
    }
    vec3 behind = texture(scene_color, bent).rgb;
    float scattering = body.albedo.w;
    vec3 absorption = 1.0 / max(body.absorption.xyz, vec3(0.001));
    vec3 extinction = absorption + vec3(scattering);
    vec3 transmittance = exp(-extinction * thickness);
    vec3 toward_sun = normalize(lighting.sun_toward.xyz);
    float sun_height = max(toward_sun.y, 0.0);
    vec3 arriving = lighting.sun_radiance.rgb * sun_height * sun_visibility(world_position, vec3(0.0, 1.0, 0.0)) + lighting.sky_radiance.rgb * pi;
    float specular = body.extent.w;
    vec3 at_normal = vec3(0.08 * specular);
    float normal_dot_eye = clamp(dot(normal, toward_eye), 0.0, 1.0);
    float complement = 1.0 - normal_dot_eye;
    float fresnel = at_normal.x + (1.0 - at_normal.x) * complement * complement * complement * complement * complement;
    // Single scattering with an isotropic phase function, of the light that entered through the surface.
    vec3 inscattered = body.albedo.rgb * scattering / extinction * arriving * (1.0 - at_normal.x) / (4.0 * pi) * (1.0 - transmittance);
    vec3 under = behind * transmittance + inscattered;
    vec3 reflected_sky = lighting.sky_radiance.rgb;
    vec3 radiance = mix(under, reflected_sky, fresnel);
    float alpha = max(body.extent.z, minimum_roughness);
    Surface surface = Surface(normal, toward_eye, vec3(0.0), at_normal, 1.0, alpha * alpha);
    radiance += reflectance(surface, toward_sun) * lighting.sun_radiance.rgb * sun_visibility(world_position, normal);
    float optical_depth = fog_optical_depth(eye, world_position);
    float fog_transmittance = exp(-optical_depth);
    radiance = radiance * fog_transmittance + lighting.sky_radiance.rgb * (1.0 - fog_transmittance);
    color = vec4(min(radiance, vec3(60000.0)), 1.0);
}
