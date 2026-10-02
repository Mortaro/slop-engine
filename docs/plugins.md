# Plugins

Everything but the core is a plugin, and a program opts into one by loading its folder. Plugins are made to be
swapped: the operating system, the renderer, the input devices and a game's look are each a plugin, and replacing
one is one `load` line.

## Naming and layout

- **Engine plugins** live in `plugins/slop_<feature>_plugin/` (the snake_case Spite requires for folders).
  Inside, a folder named like the feature is the namespace:
  `plugins/slop_window_plugin/window/component/window.spite` is `Window.Component.Window`. The inner folder keeps
  each plugin's `Component`, `System` and `Bundle` apart from every other plugin's.
- **A plugin keeps its assets inside its namespace folder**, next to the recipes that cook them:
  `slop_render_vulkan_plugin/render_vulkan/assets/shader/rectangles/vertex.glsl`.
- **A game's own plugins** (things a project can replace, like its theme) live beside the program, never inside
  it, because a program's subfolders always load: `examples/click_counter_theme_plugin/theme/` holds the
  theme's `assets/`, `recipe/` and `system/`. The game loads it with `load "../click_counter_theme_plugin"`.

## Platforms and devices

A platform is a plugin. `slop_window_plugin` and `slop_input_plugin` are platform-neutral: window data, the mouse
and keyboard state, and the `Input.Component.Event` entities a platform produces. `slop_windows_plugin` is Win32: it creates
the windows and turns their messages into event entities. Another OS, or a console, is another plugin
producing the same events; a controller family (XInput, a console pad) is a plugin producing its own device
components.

`slop_platform_plugin` picks the platform from `Build` (`if build.target_operating_system == "windows"
{ load "../../slop_windows_plugin" }`, folded at compile time), which is how a program loads it.

A source format is a plugin too. `slop/` knows only the assets it contributes; `slop_psd_plugin`,
`slop_blend_plugin` and `slop_zstd_plugin` are loaded by whoever has a recipe that reads that format, usually a theme
or a game's own plugin ([loaders.md](loaders.md)).

## A theme is one plugin

A game describes structure and meaning; its theme describes looks. The click counter's `CounterButton` bundle is a
flex container marked `Component.ButtonPrimary`, with no size, texture or colour. `click_counter_theme_plugin`
dresses it: `Theme.System.DressPrimaryButtons` gives every new primary button its size and plate, the four state
systems swap plates on hover and press, and its recipe cuts the plates out of its own PSD.
`click_counter_flat_theme_plugin` does the same with flat colours. Swapping one for the other is the one `load`
line, and the game compiles either way.

## slop_window_plugin

Platform-neutral windows: a window entity carries its data, and its per-window state (its mouse, keyboard and event
queue, and whatever the render plugins add).

| | |
|---|---|
| `Window.Component.Window` | `title`, `width` (640), `height` (400): plain data, any thread |
| `Window.Component.Hidden` | marker: the window is created hidden (tests, benchmarks) |
| `Window.Component.Handle` | `value`: the platform's native window handle, added by the platform once it has created the window; [pinned](ecs.md#components-pinned-to-a-thread) to the thread that created it |
| `Window.Bundle.Window` | a `Window` and the input plugin's `Mouse` and `Keyboard` |

"The window entity exists" is `Added<Window.Component.Window>`; "the window is open" is
`Added<Window.Component.Handle>`, which is what the Vulkan renderer waits for. A platform opens every window that has
no `Handle` yet.

## slop_windows_plugin

Win32 delivers a window's messages only to the thread that created it, so `Window.Component.Handle` is pinned to
its thread, and the systems below, which touch it, all run on the app's thread. `Windows.WindowClass` (a resource)
registers the window class once and creates each window.

| | |
|---|---|
| `Windows.System.OpenWindow` (`input`) | creates every window without a `Handle` (hidden if it has `Hidden`) and adds its `Handle` |
| `Windows.System.PumpMessages` (`input`) | takes every message waiting for the app's thread, translates mouse and keyboard messages into event entities, children of their window, and dispatches them; notices a closed window, removes its entity and adds `Component.Quit` to the world entity |
| `Windows.System.TrackWindowSize` (`input`) | copies each window's client size into its `Window` |

Messages are taken once a tick, so a window is as responsive as the frame rate, and dragging a window by its title
bar holds the tick until the drag ends, as in any engine that pumps messages on its game thread.

## slop_xinput_plugin

Windows controllers through XInput (`xinput1_4.dll`). `Xinput.System.PollGamepads` (`input`) creates a gamepad
entity when a controller connects, fills its `Input.Component.Gamepad` every tick and keeps one child entity per
held button (`Input.Component.GamepadButton`, marked `JustPressed` on the tick it went down and `JustReleased` on
the tick it went up, then despawned); an empty slot is asked only
once a second, since XInput is slow to answer for a disconnected controller. `slop_platform_plugin` loads it on
Windows. A console's controllers would be another plugin filling the same component.

## slop_input_plugin

Platform-neutral input. A platform spawns one entity per input event (pointer moved, button pressed or released,
wheel turned, key pressed or released, character typed), a child of its window holding `Input.Component.Event`, in
the order they happened, so their ids are their order; `Input.System.ApplyEvents` (`after_input`) resets the
per-tick state and applies them to the window's `Mouse` and key entities, before any UI system reads them, and
`Input.System.ForgetEvents` (`last`) despawns them. Held keys are entities too: a key is a child of its window
holding `Input.Component.Key`, so a system asks for keys held or pressed with a row, and nothing is a list of codes.

| | |
|---|---|
| `Input.Component.Event` | on an event entity (a child of its window): one input event, independent of the platform; lives one tick |
| `Input.Component.DoubleClick` | marker on a button-pressed event that was a double click |
| `Input.Component.Key` | `code`: a held key, on a child of its window; despawned the tick after it is released |
| `Input.Component.JustPressed`, `JustReleased` | markers on a key or gamepad button: it went down, or up, this tick |
| `Input.Component.GamepadButton` | `code` (an `Input.Button` name): a held controller button, on a child of its gamepad |
| `Input.Component.Gamepad` | one controller: `slot`, sticks (`left_x`, `left_y`, `right_x`, `right_y`, -1 to 1, dead zone applied) and triggers (0 to 1) |
| `Input.Component.GamepadConnected` | marker on a gamepad: its controller answered this tick; removed when it stops answering |
| `Input.Button` | platform-neutral button names: `south`, `east`, `west`, `north`, the d-pad, `start`, `select`, shoulders, stick clicks |
| `Input.Component.Keyboard` | marker on a window: it takes keys |
| `Input.Key` | names for virtual keys (`backspace`, `left`, `delete`, ...) |
| `Input.Component.Mouse` | on a window: `left`, `top` (pixels in the window) and `wheel` (notches), for the current tick |
| `Input.Component.LeftDown`, `LeftPressed`, `LeftReleased`, `DoubleClicked` | markers on a window: the left button is held, went down this tick, went up this tick, was double-clicked this tick; `Right…` and `Middle…` are the same for the other buttons |

## slop_ui_plugin

| | |
|---|---|
| `Ui.Component.Screen` | the root of an element tree; `width` and `height` are the viewport it fills |
| layout components | one per CSS property: `Display`, `FlexDirection`, `Width`, `Margin`, ... (see [ui.md](ui.md)) |
| `Ui.Component.ComputedLayout` | the border box the layout computed: `left`, `top`, `width`, `height` |
| `Ui.Component.ContentSize` | a leaf's own size, measured from its content |
| `Ui.Component.Text` | text: `text`, `scale`, `color` |
| `Ui.Component.BackgroundImage` | `texture`: an asset id |
| `Ui.Component.BackgroundColor` | `color` |
| `Ui.Component.OverflowX`, `OverflowY`, `ScrollPosition`, `ScrollRange`, `ComputedClip` | scrolling and clipping (see [ui.md](ui.md#scrolling-and-clipping)) |
| `Ui.Component.Focusable`, `Focused`, `TextInput`, `Caret` | focus and text editing (see [ui.md](ui.md#focus-and-text-input)) |
| `Ui.Component.ZIndex` | `value`: paint order among siblings (see [ui.md](ui.md#paint-order)) |
| `Ui.Component.Button` | marker: pressable |
| `Ui.Component.Hovered`, `Pressed`, `Clicked` | markers |
| `Ui.System.Interact` (`after_input`) | adds and removes the three markers from each window's mouse |
| `Ui.System.Scroll` (`after_input`) | the mouse wheel scrolls the smallest scrollable element under the pointer |
| `Ui.System.Focus`, `Ui.System.EditText` (`after_input`) | focus follows presses; the focused text input takes keys and characters |
| `Ui.System.FollowWindow` (`prepare`) | sizes every `Screen` to the window |
| `Ui.System.MeasureText` (`prepare`) | writes `ContentSize` for every `Text` |
| `Ui.System.ComputeLayout` (`layout`) | flexbox over every tree |

See [ui.md](ui.md).

## slop_render_plugin

| | |
|---|---|
| `Render.Component.DrawList` | on a draw target: this frame's rectangles, solid or textured, in raw memory |
| `Render.Textures` | a resource (singleton): asset id to slot, each slot's texture entity, and the background loads in flight, keyed by entity |
| `Component.Loading` | core marker on any entity whose asset job is in flight (a texture's, a mesh's, a terrain material's), added when the job starts and removed when its result lands, so a loading screen can ask for `Texture` + `Loading` |
| `Render.Component.Texture` | on a texture's own entity: its `id`, `slot`, decoded `image`, `raw` texels for the GPU, `generation` (bumped on every load) and the catalog revision it was loaded at |
| `Render.Component.TextureReady` | marker on a texture's entity: its texels are loaded |
| `Render.Component.ClearColor` | on a draw target: the clear colour |
| `Render.Font` | the built-in 5x7 font (a plain class) |
| `Render.System.AdoptWindows` (`after_input`) | makes each new window a draw target |
| `Render.System.BeginFrame` (`prepare`) | starts each window's draw list at the window's size |
| `Render.System.DrawUi` (`render`) | paints every laid-out element in tree order: background colour, image, text, then its scrollbars |
| `Render.System.FinishTextureLoads` (`last`) | takes finished loading jobs' textures, and reloads every texture whose cooked record changed in `Recipes.Catalog` (see [hot reload](assets-and-recipes.md#hot-reload-change-a-source-see-it-in-the-game)) |

A draw target is any entity with the three components; `render_parity` makes an offscreen one with no window.

## slop_render_software_plugin

| | |
|---|---|
| `RenderSoftware.Component.Canvas` | on a draw target: a framebuffer in raw memory |
| `RenderSoftware.System.AdoptDrawLists` (`render`) | gives each new draw target a canvas |
| `RenderSoftware.System.Rasterize` (`after_render`) | fills the canvas from the draw list, sampling and blending textures |
| `RenderSoftware.System.Present` (`present`) | blits the canvas to the window with GDI |

## slop_render_vulkan_plugin

| | |
|---|---|
| `RenderVulkan.Renderer` | a resource (singleton): the one Vulkan device, pipeline, frames in flight, upload stream, and each surface's swapchain images and per-image semaphores (`RenderVulkan.Presentation`, so it can release them); one device is shared by every window |
| `RenderVulkan.Component.GpuTexture` | on a texture's entity: its uploaded image, memory, view, descriptor set and the generation uploaded; added by `AttachGpuTextures` (`last`) to every new texture |
| `RenderVulkan.Component.Device` | on a window: what the chosen GPU offers, its `name` and `maximum_anisotropy` (1 when it has no anisotropic filtering) |
| `RenderVulkan.Component.Swapchain` | a window's surface, swapchain, size, and the image acquired this frame |
| `RenderVulkan.Component.SwapchainOutOfDate` | marker: the last acquire or present found the swapchain stale, so the next frame rebuilds it |
| `RenderVulkan.System.CreateRenderer` (`present`) | makes the device on the first window, and gives each new window a `Device` and a swapchain |
| `RenderVulkan.System.DrawFrame` (`present`) | draws the list offscreen, blits it to the swapchain, presents |
| `RenderVulkan.Component.CaptureRequested`, `Captured` | markers on a window: add `CaptureRequested` to read back the next presented frame; `DrawFrame` swaps it for `Captured` once the pixels are read |
| `RenderVulkan.System.ReleaseRenderer` (`last`) | releases the renderer once the world entity has `Component.Quit` |
| `RenderVulkan.Recipe.Shaders` | compiles the rectangle shaders |

See [rendering.md](rendering.md).

## slop_network_plugin

Replicates components between the environments of one program: state a component declares with
`mirrored_from(environment)`, and messages it declares with `sent_from(environment)`. Connections are entities;
`Network.Component.Listen` or `Network.Component.Connect` on the world entity starts it. The wire is binary frames
encoded by the engine's derived codec. TCP through the library's non-blocking `Socket`. See
[networking.md](networking.md).

## slop_spatial_plugin

A uniform grid over the ground plane, for area of interest, sight and aggro.
`Spatial.Grid()` is a singleton holding one grid per **space**, so maps that share coordinates (dungeons, instances)
never see each other. `Spatial.Component.Indexed { space }` puts an entity in a space (0 by default, or a map
entity's id). `grid.configure(space, left, top, width, depth, cell_size)` sizes a space's cells; a space never
configured covers 16 km around the origin in 32 m cells.

Every entity with `Indexed` and a `Transform.Component.Transform` is indexed each tick: `ClearGrid` empties every
space in `input`, and `IndexGrid` inserts each entity at its `position_x`/`position_z` in `after_input`, so systems
in `update` query where everyone stood at the start of the tick. `grid.within(space, x, z, radius, found)` appends
the ids within `radius` in that space.

Each cell is a linked list through entity ids, shared by every space since an entity is in one, so indexing is one
write per entity and clearing resets only the cells used. `server_bench` (15,000 entities) ticks in about 6 ms with
10,000 aggro queries of 20 m and 5,000 of 60 m, and checks a query against brute force.

## slop_interest_plugin

Observing by distance: `Interest.Component.Viewer` and the link `Interest.Component.Viewpoint` on a connection
entity, and the `MarkObserved` and `Gather` systems that keep an observation (a child holding
`Network.Component.Observer`) on every indexed entity in a viewer's range. It
loads the network and spatial plugins. See [networking.md](networking.md#area-of-interest).

## slop_mongodb_plugin

The engine side of MongoDB. The driver itself (BSON, OP_MSG, `Mongo.Client`, `Mongo.Collection`,
`Mongo.TypedCollection<T>`, the compile-time `Mongo.Codec<T>`) is its own package, `spite_mongodb_driver`, beside
this repository, so programs that are not games use it too. The plugin loads it
(`load "../../../../spite_mongodb_driver@ea1a143/mongodb"`, a pinned commit) and adds `Mongo.Component.Database` (host, port, database
name) and `Mongo.Component.Client` (a connection pool and the database it names), which `database.connect()` makes;
`Mongo.System.ConnectDatabases` (`input`) adds one beside every database that has none. Queries run in
[IO systems](ecs.md#io-systems), between frames.

---

Next: [UI](ui.md), elements as entities and layout as one component per CSS property.
