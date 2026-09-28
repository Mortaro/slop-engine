# Rendering

## The draw list

Systems never draw pixels. The `render` phase fills each draw target's `Render.Component.DrawList`: a list of rectangles in raw memory,
24 bytes each: left, top, width, height (floats), a 0x00RRGGBB colour, and a texture slot (-1 for solid). Text is one
rectangle per lit cell of the built-in 5x7 font. A backend turns the list into a frame in the `after_render` and
`present` phases. A game picks the backend by the plugin it loads.

## The software backend

`RenderSoftware.System.Rasterize` fills `RenderSoftware.Component.Canvas`, a framebuffer in raw memory, from the list:
solid rectangles are filled, textured ones are sampled nearest-neighbour (texel = pixel inside the rectangle x texture
size / rectangle size, in integers) and blended with straight alpha,
`(above x alpha + below x (255 - alpha) + 127) / 255` per channel. `Present` blits the canvas with GDI
`StretchDIBits`.

## The Vulkan backend

`vulkan-1.dll` is called through `DynamicLibrary` alone: no bindings, no loader, no C. It uses:

- Vulkan 1.3 with dynamic rendering; the GPU is chosen discrete first;
- the validation layer when the build is not `--optimized` (its output goes to stdout);
- one pipeline, whose vertex input is the draw list itself, per instance; the vertex shader makes each rectangle's
  two triangles, and the fragment shader picks the texel with the software backend's integer arithmetic;
- straight alpha blending in the pipeline;
- one descriptor set per texture, and a 1x1 white texture for solid rectangles, so consecutive rectangles with the
  same texture are one instanced draw and draw order is kept;
- an offscreen B8G8R8A8 target, blitted to the swapchain (mailbox when the driver has it, FIFO otherwise), with a
  semaphore per swapchain image;
- readback: `draw_offscreen` copies the frame into host memory, which is how the parity test reads it.

- two frames in flight (`RenderVulkan.Frame`): each has its own command buffer, fence, acquire semaphore, vertex
  buffer, offscreen target and in-flight staging buffers, and a frame waits only for the fence of the frame two
  before it.

A texture that finished loading is copied into the frame's persistent staging buffer and from there into its image
by the frame's own command buffer, at most `upload_budget_bytes` (4 MiB) per frame, shared with mesh uploads. A
larger texture streams in bands of rows over several frames and replaces the old image only after its last band. A draw whose texture is not resident yet is skipped, as it is before the texture has loaded. See
[performance.md](performance.md#no-stutters). The device is released by
`ReleaseRenderer` in the final tick after quit, not at program exit.

C structs are written by `RenderVulkan.Structure`, which appends fields in declaration order and pads each to its
natural alignment, so a struct reads like its C definition.

## Parity

`examples/render_parity` renders the click counter's screen, including the PSD button plate and its alpha edges,
through both backends and compares every pixel. Today: 0 of 256,000 differ.

## The window without callbacks

Spite can't pass a function to C yet, so there is no window procedure written in Spite. `OpenWindow` registers a
window class whose procedure is `DefWindowProcA` itself, found with `GetProcAddress`. `PumpMessages` reads mouse
and keyboard messages (`WM_KEYDOWN`, `WM_KEYUP`, `WM_CHAR`) out of the queue with `PeekMessageA` before dispatching
them, and notices a closed window when `IsWindow` turns false. Resizing, fullscreen and IME need a real callback;
they wait on the language.
