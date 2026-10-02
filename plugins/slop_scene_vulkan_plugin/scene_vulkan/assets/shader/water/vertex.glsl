#version 450
#extension GL_GOOGLE_include_directive : require

// A square grid of quads around the camera, made from the vertex index alone, packed toward the eye (each side's
// coordinate squared), clamped to the water body's extent and displaced by its Gerstner waves.

#include "waves.glsl"

const uint grid_quads = 256u;

layout(location = 0) out vec3 world_normal;
layout(location = 1) out vec2 surface_coordinate;
layout(location = 2) out vec3 world_position;
layout(location = 3) flat out uint surface_masked;

void main() {
    uint quad = uint(gl_VertexIndex) / 6u;
    uint corner = uint(gl_VertexIndex) % 6u;
    uvec2 corner_offsets[6] = uvec2[6](uvec2(0u, 0u), uvec2(0u, 1u), uvec2(1u, 0u), uvec2(1u, 0u), uvec2(0u, 1u), uvec2(1u, 1u));
    uvec2 point = uvec2(quad % grid_quads, quad / grid_quads) + corner_offsets[corner];
    vec2 unit = vec2(point) / float(grid_quads) * 2.0 - 1.0;
    vec2 packed = sign(unit) * unit * unit;
    WaterBody body = water.bodies[push.body];
    vec2 ground = water.grid.xy + packed * water.grid.z;
    ground = clamp(ground, body.place.xz - body.extent.xy, body.place.xz + body.extent.xy);
    vec3 eye = vec3(water.grid.x, body.place.y, water.grid.y);
    float distance_to_eye = distance(vec3(ground.x, body.place.y, ground.y), eye);
    vec3 displaced;
    vec3 normal;
    gerstner(body, ground, distance_to_eye, displaced, normal);
    world_normal = normal;
    surface_coordinate = ground;
    world_position = displaced;
    surface_masked = 0u;
    gl_Position = water.view_projection * vec4(displaced, 1.0);
}
