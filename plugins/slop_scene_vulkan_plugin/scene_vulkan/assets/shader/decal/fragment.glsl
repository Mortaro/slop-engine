#version 450
#extension GL_GOOGLE_include_directive : require

layout(push_constant) uniform Push {
    mat4 view_projection;
    mat4 inverse_view_projection;
} push;

layout(set = 0, binding = 0) uniform sampler2D scene_depth;

struct Decal {
    mat4 model;
    mat4 inverse;
    vec4 tint;
    vec4 shading;
};

layout(std430, set = 0, binding = 1) readonly buffer Decals {
    Decal decals[];
};

layout(set = 2, binding = 0) uniform sampler2D decal_texture;

#include "../scene/lit.glsl"

layout(location = 4) flat in uint decal_index;

// A box decal: the scene's depth gives the surface behind each pixel; the box's local x and z, from -0.5 to 0.5,
// are its texture coordinates, so it projects along its local y.
void main() {
    vec2 screen = gl_FragCoord.xy / vec2(textureSize(scene_depth, 0));
    float depth = texelFetch(scene_depth, ivec2(gl_FragCoord.xy), 0).r;
    vec4 unprojected = push.inverse_view_projection * vec4(screen * 2.0 - 1.0, depth, 1.0);
    vec3 position = unprojected.xyz / unprojected.w;
    vec3 across = dFdx(position);
    vec3 down = dFdy(position);
    Decal decal = decals[decal_index];
    vec3 local = (decal.inverse * vec4(position, 1.0)).xyz;
    vec2 coordinate = local.xz + 0.5;
    vec4 texel = textureGrad(decal_texture, coordinate, dFdx(coordinate), dFdy(coordinate));
    if (depth <= 0.0 || any(greaterThan(abs(local), vec3(0.5)))) {
        discard;
    }
    vec3 base = linear_from_srgb(texel.rgb) * decal.tint.rgb;
    float coverage = clamp(texel.a * decal.tint.a, 0.0, 1.0);
    float exposure = lighting.material.w;
    vec3 radiance = base * decal.shading.x * exposure;
    if (decal.shading.y == 0.0) {
        vec3 normal = facing_normal(cross(down, across), position);
        radiance += lit_radiance(base, normal, vec3(0.7, 0.5, 0.0), position);
    }
    color = vec4(min(fogged(radiance, position), vec3(60000.0)), coverage);
}
