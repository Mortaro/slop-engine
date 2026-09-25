#version 450

layout(set = 0, binding = 0) uniform sampler2D base_color;

layout(location = 0) in vec3 world_normal;
layout(location = 1) in vec2 surface_coordinate;

layout(location = 0) out vec4 color;

void main() {
    vec4 texel = texture(base_color, surface_coordinate);
    if (texel.a < 0.5) {
        discard;
    }
    vec3 light = normalize(vec3(0.45, 0.82, 0.35));
    float shade = 0.35 + 0.65 * max(dot(normalize(world_normal), light), 0.0);
    color = vec4(texel.rgb * shade, 1.0);
}
