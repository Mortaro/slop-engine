#version 450
// shader.rectangles.fragment: the rectangle's 0x00RRGGBB colour times its texture's texel, picked with the
// software backend's integer arithmetic (texel = pixel inside the rectangle * texture size / rectangle size).
// A solid rectangle is bound to a 1x1 white texture. Blending is straight alpha, done by the pipeline.
// A pixel outside the rectangle's clip (left, top, right, bottom; right and bottom exclusive) is written fully
// transparent, which straight-alpha blending turns into no change, as the software backend skips it. (discard would
// need the demote-to-helper-invocation device feature under Vulkan 1.3.)

layout(set = 0, binding = 0) uniform sampler2D image;

layout(location = 0) flat in uint vertex_colour;
layout(location = 1) flat in vec4 vertex_rectangle;
layout(location = 2) flat in ivec4 vertex_clip;
// The texels the rectangle shows (left, top, width, height); a zero width means the whole texture.
layout(location = 3) flat in ivec4 vertex_source;
layout(location = 0) out vec4 result;

void main() {
    ivec2 size = textureSize(image, 0);
    ivec2 pixel = ivec2(floor(gl_FragCoord.xy));
    if (pixel.x < vertex_clip.x || pixel.y < vertex_clip.y || pixel.x >= vertex_clip.z || pixel.y >= vertex_clip.w) {
        result = vec4(0.0);
        return;
    }
    ivec4 source = vertex_source;
    if (source.z == 0) {
        source = ivec4(0, 0, size);
    }
    ivec2 inside = pixel - ivec2(vertex_rectangle.xy);
    ivec2 texel = source.xy + inside * source.zw / ivec2(vertex_rectangle.zw);
    texel = clamp(texel, source.xy, source.xy + source.zw - 1);
    vec4 sampled = texelFetch(image, texel, 0);
    float red = float((vertex_colour >> 16) & 255u) / 255.0;
    float green = float((vertex_colour >> 8) & 255u) / 255.0;
    float blue = float(vertex_colour & 255u) / 255.0;
    result = vec4(vec3(red, green, blue) * sampled.rgb, sampled.a);
}
