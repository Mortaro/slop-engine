#version 450
// shader.rectangles.vertex -- one instance per Render.Component.DrawList rectangle, in pixels from the top left,
// drawn as two triangles. Integer rectangles cover exactly the pixels the software backend fills.

layout(location = 0) in vec4 rectangle;
layout(location = 1) in uint colour;
layout(location = 2) in ivec4 clip;
layout(location = 3) in ivec4 source;

layout(push_constant) uniform Frame {
    vec2 size;
} frame;

layout(location = 0) flat out uint vertex_colour;
layout(location = 1) flat out vec4 vertex_rectangle;
layout(location = 2) flat out ivec4 vertex_clip;
layout(location = 3) flat out ivec4 vertex_source;

const vec2 corners[6] = vec2[](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));

void main() {
    vec2 corner = corners[gl_VertexIndex];
    vec2 pixel = rectangle.xy + corner * rectangle.zw;
    vec2 normalized = pixel / frame.size * 2.0 - 1.0;
    gl_Position = vec4(normalized, 0.0, 1.0);
    vertex_colour = colour;
    vertex_rectangle = rectangle;
    vertex_clip = clip;
    vertex_source = source;
}
