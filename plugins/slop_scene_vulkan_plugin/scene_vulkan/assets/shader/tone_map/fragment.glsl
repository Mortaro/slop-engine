#version 450

layout(set = 0, binding = 0) uniform sampler2D scene;

layout(location = 0) in vec2 surface_coordinate;

layout(location = 0) out vec4 color;

vec3 aces_fitted(vec3 linear) {
    vec3 rendering = vec3(
        dot(vec3(0.59719, 0.35458, 0.04823), linear),
        dot(vec3(0.07600, 0.90834, 0.01566), linear),
        dot(vec3(0.02840, 0.13383, 0.83777), linear));
    rendering = (rendering * (rendering + 0.0245786) - 0.000090537) / (rendering * (0.983729 * rendering + 0.4329510) + 0.238081);
    vec3 display = vec3(
        dot(vec3(1.60475, -0.53108, -0.07367), rendering),
        dot(vec3(-0.10208, 1.10813, -0.00605), rendering),
        dot(vec3(-0.00327, -0.07276, 1.07602), rendering));
    return clamp(display, 0.0, 1.0);
}

vec3 srgb_from_linear(vec3 linear) {
    vec3 clamped = max(linear, vec3(0.0));
    vec3 low = 12.92 * clamped;
    vec3 high = 1.055 * pow(clamped, vec3(1.0 / 2.4)) - 0.055;
    return mix(low, high, step(vec3(0.0031308), clamped));
}

float gradient_noise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec3 scene_radiance = texture(scene, surface_coordinate).rgb;
    vec3 encoded = srgb_from_linear(aces_fitted(scene_radiance));
    float first = gradient_noise(gl_FragCoord.xy);
    float second = gradient_noise(gl_FragCoord.xy + vec2(47.0, 17.0));
    encoded += vec3((first + second - 1.0) / 255.0);
    color = vec4(encoded, 1.0);
}
