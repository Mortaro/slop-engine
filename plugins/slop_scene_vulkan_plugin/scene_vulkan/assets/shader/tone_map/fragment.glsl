#version 450

// From pre-exposed scene light to the 8-bit frame: the bloom added, the exposure finished, Unreal's vignette,
// a tone curve (Unreal's filmic curve by default, or the ACES fit), the sRGB encoding and a dither.

layout(set = 0, binding = 0) uniform sampler2D scene;
layout(set = 0, binding = 1) uniform sampler2D bloom;

layout(std430, set = 0, binding = 6) readonly buffer Exposure {
    // the adapted EV100, 1 once it holds a value, the exposure it gives, the target EV100
    vec4 state;
} exposure;

layout(push_constant) uniform Push {
    // slope, toe, shoulder, black clip
    vec4 film;
    // white clip, curve (0 filmic, 1 ACES fit), bloom intensity, vignette intensity
    vec4 look;
    // 1 when the exposure is metered, one over this frame's pre-exposure, width, height
    vec4 exposure;
} push;

layout(location = 0) in vec2 surface_coordinate;

layout(location = 0) out vec4 color;

const float pi = 3.14159265;

// Rows written as dot products: GLSL's mat3 constructor takes columns.
vec3 multiply(vec3 row_0, vec3 row_1, vec3 row_2, vec3 value) {
    return vec3(dot(row_0, value), dot(row_1, value), dot(row_2, value));
}

// Linear sRGB to ACEScg (AP1), through the Bradford D65 to D60 adaptation, and back.
vec3 ap1_from_srgb(vec3 value) {
    return multiply(vec3(0.6131324, 0.3395381, 0.0473296), vec3(0.0701934, 0.9163539, 0.0134527), vec3(0.0206155, 0.1095697, 0.8698148), value);
}

vec3 srgb_from_ap1(vec3 value) {
    return multiply(vec3(1.7048586, -0.6217160, -0.0832993), vec3(-0.1300768, 1.1407357, -0.0105598), vec3(-0.0239640, -0.1289755, 1.1530393), value);
}

vec3 ap0_from_ap1(vec3 value) {
    return multiply(vec3(0.6954522, 0.1406787, 0.1638691), vec3(0.0447946, 0.8596711, 0.0955343), vec3(-0.0055259, 0.0040252, 1.0015007), value);
}

vec3 ap1_from_ap0(vec3 value) {
    return multiply(vec3(1.4514393, -0.2365107, -0.2149286), vec3(-0.0765538, 1.1762297, -0.0996759), vec3(0.0083161, -0.0060324, 0.9977163), value);
}

const vec3 ap1_luminance = vec3(0.2722287, 0.6740818, 0.0536895);

float saturation_of(vec3 value) {
    float lowest = min(min(value.r, value.g), value.b);
    float highest = max(max(value.r, value.g), value.b);
    return (max(highest, 1e-10) - max(lowest, 1e-10)) / max(highest, 1e-2);
}

float luma_chroma_of(vec3 value) {
    float chroma = sqrt(max(value.b * (value.b - value.g) + value.g * (value.g - value.r) + value.r * (value.r - value.b), 0.0));
    return (value.b + value.g + value.r + 1.75 * chroma) / 3.0;
}

float sigmoid_shaper(float value) {
    float shaped = max(1.0 - abs(0.5 * value), 0.0);
    return 0.5 * (1.0 + sign(value) * (1.0 - shaped * shaped));
}

float glow_of(float luma_chroma, float gain, float middle) {
    if (luma_chroma <= 2.0 / 3.0 * middle) {
        return gain;
    }
    if (luma_chroma >= 2.0 * middle) {
        return 0.0;
    }
    return gain * (middle / luma_chroma - 0.5);
}

float hue_of(vec3 value) {
    if (value.r == value.g && value.g == value.b) {
        return 0.0;
    }
    float hue = 180.0 / pi * atan(sqrt(3.0) * (value.g - value.b), 2.0 * value.r - value.g - value.b);
    return hue < 0.0 ? hue + 360.0 : hue;
}

float centred_hue(float hue, float centre) {
    float centred = hue - centre;
    if (centred < -180.0) {
        return centred + 360.0;
    }
    if (centred > 180.0) {
        return centred - 360.0;
    }
    return centred;
}

float log_10(float value) {
    return log2(value) * 0.30103;
}

// Unreal's filmic tone curve (FilmToneMap): the ACES reference rendering transform's glow and red modifier, then
// a toe, a straight section and a shoulder in log space with the five film parameters, in AP1.
vec3 filmic(vec3 linear) {
    float slope = push.film.x;
    float toe = push.film.y;
    float shoulder = push.film.z;
    float black_clip = push.film.w;
    float white_clip = push.look.x;
    vec3 colour_ap0 = ap0_from_ap1(ap1_from_srgb(linear));
    float saturation = saturation_of(colour_ap0);
    float luma_chroma = luma_chroma_of(colour_ap0);
    float shaped = sigmoid_shaper((saturation - 0.4) / 0.2);
    colour_ap0 *= 1.0 + glow_of(luma_chroma, 0.05 * shaped, 0.08);
    float hue = centred_hue(hue_of(colour_ap0), 0.0);
    float hue_weight = smoothstep(0.0, 1.0, 1.0 - abs(2.0 * hue / 135.0));
    hue_weight *= hue_weight;
    colour_ap0.r += hue_weight * saturation * (0.03 - colour_ap0.r) * (1.0 - 0.82);
    vec3 working = max(ap1_from_ap0(colour_ap0), vec3(0.0));
    working = mix(vec3(dot(working, ap1_luminance)), working, 0.96);
    float toe_scale = 1.0 + black_clip - toe;
    float shoulder_scale = 1.0 + white_clip - shoulder;
    float in_match = 0.18;
    float out_match = 0.18;
    float toe_match;
    if (toe > 0.8) {
        toe_match = (1.0 - toe - out_match) / slope + log_10(in_match);
    } else {
        float bt = (out_match + black_clip) / toe_scale - 1.0;
        toe_match = log_10(in_match) - 0.5 * log((1.0 + bt) / (1.0 - bt)) * (toe_scale / slope);
    }
    float straight_match = (1.0 - toe) / slope - toe_match;
    float shoulder_match = shoulder / slope - straight_match;
    vec3 log_colour = vec3(log_10(max(working.r, 1e-10)), log_10(max(working.g, 1e-10)), log_10(max(working.b, 1e-10)));
    vec3 straight = slope * (log_colour + straight_match);
    vec3 toe_colour = -black_clip + (2.0 * toe_scale) / (1.0 + exp((-2.0 * slope / toe_scale) * (log_colour - toe_match)));
    vec3 shoulder_colour = (1.0 + white_clip) - (2.0 * shoulder_scale) / (1.0 + exp((2.0 * slope / shoulder_scale) * (log_colour - shoulder_match)));
    toe_colour = mix(straight, toe_colour, lessThan(log_colour, vec3(toe_match)));
    shoulder_colour = mix(straight, shoulder_colour, greaterThan(log_colour, vec3(shoulder_match)));
    vec3 blend = clamp((log_colour - toe_match) / (shoulder_match - toe_match), 0.0, 1.0);
    blend = shoulder_match < toe_match ? 1.0 - blend : blend;
    blend = (3.0 - 2.0 * blend) * blend * blend;
    vec3 toned = mix(toe_colour, shoulder_colour, blend);
    toned = mix(vec3(dot(toned, ap1_luminance)), toned, 0.93);
    return clamp(srgb_from_ap1(max(toned, vec3(0.0))), 0.0, 1.0);
}

vec3 aces_fitted(vec3 linear) {
    vec3 rendering = multiply(vec3(0.59719, 0.35458, 0.04823), vec3(0.07600, 0.90834, 0.01566), vec3(0.02840, 0.13383, 0.83777), linear);
    rendering = (rendering * (rendering + 0.0245786) - 0.000090537) / (rendering * (0.983729 * rendering + 0.4329510) + 0.238081);
    vec3 display = multiply(vec3(1.60475, -0.53108, -0.07367), vec3(-0.10208, 1.10813, -0.00605), vec3(-0.00327, -0.07276, 1.07602), rendering);
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

// Unreal's natural vignette, the cosine-fourth law, on a circle whose corners sit at distance 1.
float vignette_of(float intensity) {
    vec2 size = push.exposure.zw;
    vec2 circle = (surface_coordinate * 2.0 - 1.0) * size / length(size) * intensity;
    float cosine_squared = 1.0 / (dot(circle, circle) + 1.0);
    return cosine_squared * cosine_squared;
}

void main() {
    vec3 radiance = texture(scene, surface_coordinate).rgb;
    float bloom_intensity = push.look.z;
    if (bloom_intensity > 0.0) {
        radiance += texture(bloom, surface_coordinate).rgb * bloom_intensity;
    }
    if (push.exposure.x > 0.5 && exposure.state.y > 0.5) {
        radiance *= exposure.state.z * push.exposure.y;
    }
    radiance *= vignette_of(push.look.w);
    vec3 toned = push.look.y > 0.5 ? aces_fitted(radiance) : filmic(radiance);
    vec3 encoded = srgb_from_linear(toned);
    float first = gradient_noise(gl_FragCoord.xy);
    float second = gradient_noise(gl_FragCoord.xy + vec2(47.0, 17.0));
    encoded += vec3((first + second - 1.0) / 255.0);
    color = vec4(encoded, 1.0);
}
