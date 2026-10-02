#version 450
#extension GL_GOOGLE_include_directive : require

// Temporal anti-aliasing and upsampling (Karis 2014): the projection moves by a sub-pixel jitter each frame, and
// the new samples are blended into the history of the same surface, reprojected from where the camera saw it last
// frame. The history is clipped to the colour box of the new samples' 3 by 3 neighbourhood in YCoCg, so a surface
// that moved cannot drag its old colour along. The output is at display size; the input may be smaller.

layout(set = 0, binding = 0) uniform sampler2D current;
layout(set = 0, binding = 1) uniform sampler2D depth_map;
layout(set = 0, binding = 2) uniform sampler2D history;

layout(push_constant) uniform Push {
    // from this frame's unjittered clip space to last frame's
    mat4 reprojection;
    // jitter in render pixels, the weight of a new sample, whether the history holds a frame (1 or 0)
    vec4 jitter;
    // render width and height, history scale (pre-exposure now over then)
    vec4 sizes;
} push;

#include "common.glsl"

layout(location = 0) out vec4 color;

const float reconstruction_sharpness = 2.0;

vec3 ycocg_from_rgb(vec3 rgb) {
    return vec3(0.25 * rgb.r + 0.5 * rgb.g + 0.25 * rgb.b, 0.5 * rgb.r - 0.5 * rgb.b, -0.25 * rgb.r + 0.5 * rgb.g - 0.25 * rgb.b);
}

vec3 rgb_from_ycocg(vec3 value) {
    return vec3(value.x + value.y - value.z, value.x + value.z, value.x - value.y - value.z);
}

vec3 clip_to_box(vec3 value, vec3 box_minimum, vec3 box_maximum) {
    vec3 centre = 0.5 * (box_maximum + box_minimum);
    vec3 extent = 0.5 * (box_maximum - box_minimum) + 1e-5;
    vec3 offset = value - centre;
    vec3 units = abs(offset / extent);
    float largest = max(units.x, max(units.y, units.z));
    return largest > 1.0 ? centre + offset / largest : value;
}

vec4 catmull_rom_weights(float fraction) {
    float squared = fraction * fraction;
    float cubed = squared * fraction;
    return vec4(
        -0.5 * cubed + squared - 0.5 * fraction,
        1.5 * cubed - 2.5 * squared + 1.0,
        -1.5 * cubed + 2.0 * squared + 0.5 * fraction,
        0.5 * cubed - 0.5 * squared);
}

// The history through a Catmull-Rom filter, which a bilinear read would blur a little every frame.
vec3 history_at(vec2 coordinate) {
    vec2 size = vec2(textureSize(history, 0));
    vec2 position = coordinate * size - 0.5;
    vec2 base = floor(position);
    vec4 across = catmull_rom_weights(position.x - base.x);
    vec4 down = catmull_rom_weights(position.y - base.y);
    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;
    for (int row = 0; row < 4; row++) {
        for (int column = 0; column < 4; column++) {
            ivec2 texel = clamp(ivec2(base) + ivec2(column - 1, row - 1), ivec2(0), ivec2(size) - 1);
            float weight = across[column] * down[row];
            sum += texelFetch(history, texel, 0).rgb * weight;
            weight_sum += weight;
        }
    }
    return max(sum / weight_sum, vec3(0.0));
}

void main() {
    vec2 render_size = push.sizes.xy;
    vec2 position = surface_coordinate * render_size;
    ivec2 nearest = ivec2(floor(position));
    ivec2 last = ivec2(render_size) - 1;
    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;
    vec3 box_minimum = vec3(1e30);
    vec3 box_maximum = vec3(-1e30);
    float closest = 0.0;
    for (int row = -1; row <= 1; row++) {
        for (int column = -1; column <= 1; column++) {
            ivec2 texel = clamp(nearest + ivec2(column, row), ivec2(0), last);
            vec3 sample_color = texelFetch(current, texel, 0).rgb;
            // The texel shows the scene at its centre less the jitter.
            vec2 offset = vec2(texel) + 0.5 - push.jitter.xy - position;
            float weight = exp(-reconstruction_sharpness * dot(offset, offset));
            sum += sample_color * weight;
            weight_sum += weight;
            vec3 converted = ycocg_from_rgb(sample_color);
            box_minimum = min(box_minimum, converted);
            box_maximum = max(box_maximum, converted);
            closest = max(closest, texelFetch(depth_map, texel, 0).r);
        }
    }
    vec3 now = sum / max(weight_sum, 1e-6);
    vec4 then = push.reprojection * vec4(surface_coordinate * 2.0 - 1.0, closest, 1.0);
    vec2 previous = then.xy / then.w * 0.5 + 0.5;
    bool inside = all(greaterThanEqual(previous, vec2(0.0))) && all(lessThanEqual(previous, vec2(1.0)));
    if (push.jitter.w < 0.5 || !inside) {
        color = vec4(now, 1.0);
        return;
    }
    vec3 remembered = history_at(previous) * push.sizes.z;
    remembered = rgb_from_ycocg(clip_to_box(ycocg_from_rgb(remembered), box_minimum, box_maximum));
    float new_weight = push.jitter.z / (1.0 + luminance_of(now));
    float old_weight = (1.0 - push.jitter.z) / (1.0 + luminance_of(remembered));
    vec3 blended = (now * new_weight + remembered * old_weight) / (new_weight + old_weight);
    color = vec4(max(blended, vec3(0.0)), 1.0);
}
