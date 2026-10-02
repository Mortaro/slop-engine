#version 450

// Unreal's histogram auto exposure: the average EV100 of the pixels between the low and the high percentile,
// clamped to the minimum and maximum, less the compensation, approached at speed up (the picture brightening)
// or speed down in stops per second: linearly while more than 1.5 stops away, exponentially closer.

layout(local_size_x = 1) in;

layout(std430, set = 0, binding = 6) buffer Exposure {
    // the adapted EV100, 1 once it holds a value, the exposure it gives, the target EV100
    vec4 state;
} exposure;

layout(std430, set = 0, binding = 7) buffer Histogram {
    uint bins[64];
} histogram;

layout(push_constant) uniform Push {
    // lowest and highest EV100 of the histogram, low and high fractions
    vec4 range;
    // minimum and maximum EV100, compensation in stops, seconds since the last frame
    vec4 limits;
    // speed up, speed down, 1 to start again from the target
    vec4 speeds;
} push;

const float transition_distance = 1.5;

void main() {
    float total = 0.0;
    for (uint bin = 0u; bin < 64u; bin++) {
        total += float(histogram.bins[bin]);
    }
    float low = total * push.range.z;
    float high = total * push.range.w;
    float below = 0.0;
    float counted = 0.0;
    float weighted = 0.0;
    float bin_width = (push.range.y - push.range.x) / 64.0;
    for (uint bin = 0u; bin < 64u; bin++) {
        float count = float(histogram.bins[bin]);
        float inside = clamp(below + count, low, high) - clamp(below, low, high);
        counted += inside;
        weighted += inside * (push.range.x + (float(bin) + 0.5) * bin_width);
        below += count;
    }
    float average = counted > 0.0 ? weighted / counted : exposure.state.w;
    float target = clamp(average, push.limits.x, push.limits.y) - push.limits.z;
    float adapted = target;
    if (exposure.state.y > 0.5 && push.speeds.z < 0.5) {
        float previous = exposure.state.x;
        float difference = target - previous;
        // A lower EV100 is a larger exposure: the picture brightens.
        float speed = difference < 0.0 ? push.speeds.x : push.speeds.y;
        float seconds = push.limits.w;
        if (abs(difference) > transition_distance) {
            adapted = previous + sign(difference) * min(speed * seconds, abs(difference));
        } else {
            adapted = previous + difference * (1.0 - exp2(-speed * seconds));
        }
    }
    exposure.state = vec4(adapted, 1.0, 1.0 / (1.2 * exp2(adapted)), target);
}
