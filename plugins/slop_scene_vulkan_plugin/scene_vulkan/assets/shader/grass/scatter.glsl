#version 450
#extension GL_GOOGLE_include_directive : require

// Scatters one grass type around the camera like Unreal's landscape grass: a jittered grid in world space, every
// choice made from a hash of the grid cell, so the same blade stands in the same place every frame.

layout(local_size_x = 8, local_size_y = 8) in;

#include "kinds.glsl"

layout(set = 0, binding = 0) uniform sampler2D ground;
layout(set = 0, binding = 1) uniform sampler2D density_map;

layout(std430, set = 0, binding = 2) readonly buffer Kinds {
    GrassKind kinds[];
};

layout(std430, set = 0, binding = 3) writeonly buffer Instances {
    vec4 instances[];
};

struct Command {
    uint index_count;
    uint instance_count;
    uint first_index;
    int vertex_offset;
    uint first_instance;
};

layout(std430, set = 0, binding = 4) buffer Commands {
    Command commands[];
};

layout(std430, set = 0, binding = 5) readonly buffer Frame {
    GrassFrame frame;
};

layout(push_constant) uniform Push {
    uint kind;
} push;

uint hash(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

float random_unit(inout uint state) {
    state = hash(state);
    return float(state >> 8) / 16777216.0;
}

bool ground_at(vec2 place, out float height, out vec3 normal) {
    float texels = frame.ground_area.w;
    vec2 unit = (place - frame.ground_area.xy) / (2.0 * frame.ground_area.z) + 0.5;
    vec2 texel = unit * texels - 0.5;
    if (texel.x < 0.0 || texel.y < 0.0 || texel.x >= texels - 1.0 || texel.y >= texels - 1.0) {
        return false;
    }
    ivec2 corner = ivec2(floor(texel));
    vec2 blend = texel - vec2(corner);
    vec4 low_left = texelFetch(ground, corner, 0);
    vec4 low_right = texelFetch(ground, corner + ivec2(1, 0), 0);
    vec4 high_left = texelFetch(ground, corner + ivec2(0, 1), 0);
    vec4 high_right = texelFetch(ground, corner + ivec2(1, 1), 0);
    if (min(min(low_left.x, low_right.x), min(high_left.x, high_right.x)) < -100000000.0) {
        return false;
    }
    vec4 mixed = mix(mix(low_left, low_right, blend.x), mix(high_left, high_right, blend.x), blend.y);
    height = mixed.x;
    normal = normalize(mixed.yzw);
    return true;
}

vec4 rotation_from_up_to(vec3 normal) {
    return normalize(vec4(normal.z, 0.0, -normal.x, 1.0 + normal.y));
}

vec4 multiplied(vec4 first, vec4 second) {
    return vec4(
        first.w * second.xyz + second.w * first.xyz + cross(first.xyz, second.xyz),
        first.w * second.w - dot(first.xyz, second.xyz));
}

void main() {
    GrassKind kind = kinds[push.kind];
    uvec2 cell = gl_GlobalInvocationID.xy;
    uint columns = uint(kind.grid.z);
    if (cell.x >= columns || cell.y >= columns) {
        return;
    }
    int column = kind.grid.x + int(cell.x);
    int row = kind.grid.y + int(cell.y);
    uint state = hash(uint(column) * 0x8da6b343u ^ hash(uint(row) * 0xd8163841u ^ uint(kind.grid.w) * 0xcb1ab31fu));
    float spacing = kind.placement.x;
    vec2 jitter = vec2(random_unit(state), random_unit(state)) - 0.5;
    vec2 place = (vec2(column, row) + 0.5 + jitter * kind.placement.y) * spacing;
    float keep = random_unit(state);
    float size = random_unit(state);
    float yaw = random_unit(state) * 6.2831853;
    float height;
    vec3 normal;
    if (!ground_at(place, height, normal)) {
        return;
    }
    vec3 position = vec3(place.x, height, place.y);
    float distance_to_eye = distance(position, frame.eye.xyz);
    float start = kind.cull.x;
    float end = kind.cull.y;
    if (distance_to_eye >= end) {
        return;
    }
    if (kind.density.w > 0.5) {
        vec4 weights = textureLod(density_map, place / kind.density.xy, 0.0);
        float weight = weights[clamp(int(kind.density.z), 0, 3)];
        if (keep >= weight) {
            return;
        }
    }
    // Unreal shrinks grass instances to nothing between the start and the end cull distance.
    float fade = 1.0 - clamp((distance_to_eye - start) / max(end - start, 0.001), 0.0, 1.0);
    float scale = mix(kind.placement.z, kind.placement.w, size) * fade;
    if (scale <= 0.0) {
        return;
    }
    uint flags = uint(kind.cull.w);
    vec4 turn = vec4(0.0, 0.0, 0.0, 1.0);
    if ((flags & 2u) != 0u) {
        turn = vec4(0.0, sin(yaw * 0.5), 0.0, cos(yaw * 0.5));
    }
    vec3 up = vec3(0.0, 1.0, 0.0);
    if ((flags & 1u) != 0u) {
        turn = multiplied(rotation_from_up_to(normal), turn);
        up = normal;
    }
    vec3 center = position + up * kind.wind.w * scale;
    float radius = (kind.cull.z + kind.wind.x * kind.wind.z) * scale;
    for (int plane = 0; plane < 4; plane++) {
        if (dot(frame.planes[plane].xyz, center) + frame.planes[plane].w < -radius) {
            return;
        }
    }
    uint first_command = kind.placement_output.z;
    uint slot = atomicAdd(commands[first_command].instance_count, 1u);
    for (uint command = 1u; command < kind.placement_output.w; command++) {
        atomicAdd(commands[first_command + command].instance_count, 1u);
    }
    uint at = (kind.placement_output.x + slot) * 2u;
    instances[at] = vec4(position, scale);
    instances[at + 1u] = turn;
}
