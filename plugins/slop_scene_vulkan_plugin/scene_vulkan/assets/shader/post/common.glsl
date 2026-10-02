// Shared by the post-processing passes (docs/scene.md#post-processing).

const float pi = 3.14159265;

layout(location = 0) in vec2 surface_coordinate;

// Luminance of linear Rec. 709 (ITU-R BT.709).
float luminance_of(vec3 linear) {
    return dot(linear, vec3(0.2126, 0.7152, 0.0722));
}

// Interleaved gradient noise (Jimenez 2014), in [0, 1).
float gradient_noise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}
