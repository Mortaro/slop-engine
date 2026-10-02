// One grass type, written by SceneVulkan.GrassPass each frame (96 bytes).
struct GrassKind {
    // first grid column, first grid row, columns (and rows) in the square, seed
    ivec4 grid;
    // grid spacing in metres, placement jitter, smallest scale, largest scale
    vec4 placement;
    // start and end cull distance, mesh bounding radius, flags (1 align to surface, 2 random yaw)
    vec4 cull;
    // density map width and depth in metres, channel, whether there is a map
    vec4 density;
    // first instance, instance capacity, first indirect command, command count
    uvec4 placement_output;
    // wind strength, wind speed, mesh height, height of the mesh's bounding centre
    vec4 wind;
};

// The frame's shared values: the four side planes of the view (normalised), the eye and the time in seconds, and the
// ground capture's centre x and z, half size in metres and texels per side.
struct GrassFrame {
    vec4 planes[4];
    vec4 eye;
    vec4 ground_area;
};

// Each placed instance is two vec4: its position and scale, then its rotation quaternion.
