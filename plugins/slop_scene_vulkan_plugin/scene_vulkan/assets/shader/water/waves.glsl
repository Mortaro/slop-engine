// The water surfaces of the frame, written by SceneVulkan.WaterPass.

struct WaterBody {
    // centre x, surface height, centre z, unused
    vec4 place;
    // half extent x and z in metres, roughness, specular
    vec4 extent;
    // albedo rgb, scattering per metre
    vec4 albedo;
    // absorption distance in metres for red, green and blue, unused
    vec4 absorption;
    // first wave, wave count
    uvec4 waves;
};

layout(std430, set = 0, binding = 2) readonly buffer WaterFrame {
    mat4 view_projection;
    mat4 inverse_view_projection;
    // grid centre x and z, grid reach in metres, time in seconds
    vec4 grid;
    // target width and height, and their inverses
    vec4 screen;
    WaterBody bodies[];
} water;

// Each wave is two vec4: direction x and z, wave number (2 pi / wavelength), amplitude; then the horizontal
// amplitude (steepness / wave number), the angular frequency, and two unused.
layout(std430, set = 0, binding = 3) readonly buffer Waves {
    vec4 waves[];
};

layout(push_constant) uniform Push {
    uint body;
} push;

// The sum of a body's Gerstner waves at an undisplaced point: the displaced position and the surface normal. A wave
// fades out where it is too short for the distance to show it, so the far sea does not sparkle.
void gerstner(WaterBody body, vec2 ground, float distance_to_eye, out vec3 displaced, out vec3 normal) {
    vec3 offset = vec3(0.0);
    vec3 slope = vec3(0.0, 1.0, 0.0);
    float time = water.grid.w;
    for (uint index = 0u; index < body.waves.y; index++) {
        uint at = (body.waves.x + index) * 2u;
        vec4 shape = waves[at];
        vec4 motion = waves[at + 1u];
        vec2 direction = shape.xy;
        float wave_number = shape.z;
        float wavelength = 6.2831853 / wave_number;
        float fade = clamp(2.0 - distance_to_eye / (wavelength * 40.0), 0.0, 1.0);
        float amplitude = shape.w * fade;
        float horizontal = motion.x * fade;
        float phase = wave_number * dot(direction, ground) - motion.y * time;
        float rise = sin(phase);
        float along = cos(phase);
        offset.xz += direction * horizontal * along;
        offset.y += amplitude * rise;
        slope.xz -= direction * wave_number * amplitude * along;
        slope.y -= wave_number * horizontal * rise;
    }
    displaced = vec3(ground.x, body.place.y, ground.y) + offset;
    normal = normalize(slope);
}
