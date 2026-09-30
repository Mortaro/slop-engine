# Plugins

Everything but the core is a plugin, and a program opts into one by loading its folder. Plugins are made to be
swapped: the operating system, the renderer, the input devices and a game's look are each a plugin, and replacing
one is one `load` line.

## Naming and layout

- **Engine plugins** live in `plugins/slop_<feature>_plugin/` (the snake_case Spite requires for folders,
  D181). Inside, a folder named like the feature is the namespace:
  `plugins/slop_window_plugin/window/component/window.spite` is `Window.Component.Window`. The inner folder keeps
  each plugin's `Component`, `System` and `Bundle` apart from every other plugin's.
- **A plugin keeps its assets inside its namespace folder**, next to the recipes that cook them:
  `slop_render_vulkan_plugin/render_vulkan/assets/shader/rectangles/vertex.glsl`.
- **A game's own plugins** (things a project can replace, like its theme) live beside the program, never inside
  it, because a program's subfolders always load (D182): `examples/click_counter_theme_plugin/theme/` holds the
  theme's `assets/`, `recipe/` and `system/`. The game loads it with `load "../click_counter_theme_plugin"`.

## Platforms and devices

A platform is a plugin. `slop_window_plugin` and `slop_input_plugin` are platform-neutral: window data, the mouse
and keyboard state, and the `Input.Event` records a platform produces. `slop_windows_plugin` is Win32: its window
thread owns the windows and turns their messages into `Input.Event`s. Another OS, or a console, is another plugin
producing the same events; a controller family (XInput, a console pad) is a plugin producing its own device
components.

`slop_platform_plugin` picks the platform from `Build` (`if build.target_operating_system == "windows"
{ load "../../slop_windows_plugin" }`, folded at compile time, D186), which is how a program loads it.

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
| `Window.Component.Handle` | `value`: the platform's native window handle, 0 until the platform has created it |
| `Window.Component.Opening` | `slot`: the window's pending request to the platform |
| `Window.Component.Requested` | marker: this window has not been opened yet |
| `Window.Bundle.Window` | a `Window`, a `Handle`, a `Requested`, and the input plugin's `Mouse`, `Keyboard` and `Events` |

"The window entity exists" is `Added<Window.Component.Window>`; "the window is open" (it has a handle) is
`Removed<Window.Component.Opening>`, which is what the Vulkan renderer waits for.

## slop_windows_plugin

Win32. The windows belong to a dedicated window thread: `Windows.Owner` (a singleton the systems call briefly)
starts `Windows.Pump`, a plain object holding only the shared raw memory, whose loop creates windows on request,
pumps their messages continuously (even while a frame takes long) and records mouse and keyboard messages into a buffer in raw
memory behind an SRW lock; no system is tied to a thread.

| | |
|---|---|
| `Windows.System.OpenWindow` (`input`) | asks the window thread for every requested window, then swaps `Requested` for `Opening` |
| `Windows.System.FinishOpening` (`after_input`) | takes the handle once the window exists and removes `Opening` |
| `Windows.System.PumpMessages` (`input`) | translates the window thread's messages into `Input.Event`s on each window's `Events`, notices a closed window, removes its entity and adds `Component.Quit` to the world entity |
| `Windows.System.StopWindows` (`last`) | stops the window thread once the world entity has `Component.Quit` |

## slop_xinput_plugin

Windows controllers through XInput (`xinput1_4.dll`). `Xinput.System.PollGamepads` (`input`) creates a gamepad
entity when a controller connects, and fills its `Input.Component.Gamepad` every tick; an empty slot is asked only
once a second, since XInput is slow to answer for a disconnected controller. `slop_platform_plugin` loads it on
Windows. A console's controllers would be another plugin filling the same component.

## slop_input_plugin

Platform-neutral input. A platform appends `Input.Event`s (pointer moved, button pressed or released, wheel turned,
key pressed or released, character typed) to a window's `Input.Component.Events`; `Input.System.ApplyEvents`
(`after_input`) resets the per-tick state and applies them to the window's `Mouse` and `Keyboard`, before any UI
system reads them.

| | |
|---|---|
| `Input.Event` | one input event, independent of the platform |
| `Input.Component.Gamepad` | one controller: `slot`, `held`/`pressed`/`released` buttons, sticks (`left_x`, `left_y`, `right_x`, `right_y`, -1 to 1, dead zone applied) and triggers (0 to 1) |
| `Input.Component.GamepadConnected` | marker on a gamepad: its controller answered this tick; removed when it stops answering |
| `Input.Button` | platform-neutral button names: `south`, `east`, `west`, `north`, the d-pad, `start`, `select`, shoulders, stick clicks |
| `Input.Component.Events` | `pending`: the events a platform delivered this tick |
| `Input.Component.Keyboard` | on a window: `held` and `pressed` keys, `typed` characters, and `strokes` (key presses and characters in order) for the current tick |
| `Input.Key` | names for virtual keys (`backspace`, `left`, `delete`, ...) |
| `Input.Component.Mouse` | on a window: `left`, `top` (pixels in the window) and `wheel` (notches), for the current tick |
| `Input.Component.LeftDown`, `LeftPressed`, `LeftReleased`, `DoubleClicked` | markers on a window: the left button is held, went down this tick, went up this tick, was double-clicked this tick; `Right…` and `Middle…` are the same for the other buttons |

## slop_ui_plugin

| | |
|---|---|
| `Ui.Component.Screen` | the root of an element tree; `width` and `height` are the viewport it fills |
| `Ui.Component.Parent` | the element's parent entity |
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
| `Render.Component.Textures` | on a draw target: asset id to slot, each slot's texture entity, and the background loads in flight |
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
| `RenderVulkan.Component.Renderer` | on a window: the device, pipeline, frames in flight, textures and swapchains |
| `RenderVulkan.Component.Device` | on a window: what the chosen GPU offers, its `name` and `maximum_anisotropy` (1 when it has no anisotropic filtering) |
| `RenderVulkan.Component.Swapchain` | a window's surface, swapchain, images and per-image semaphores |
| `RenderVulkan.Component.SwapchainOutOfDate` | marker: the last acquire or present found the swapchain stale, so the next frame rebuilds it |
| `RenderVulkan.System.CreateRenderer` (`present`) | gives each new window a device, a renderer and a swapchain |
| `RenderVulkan.System.DrawFrame` (`present`) | draws the list offscreen, blits it to the swapchain, presents |
| `RenderVulkan.Component.CaptureRequested`, `Captured` | markers on a window: add `CaptureRequested` to read back the next presented frame; `DrawFrame` swaps it for `Captured` once the pixels are read |
| `RenderVulkan.System.ReleaseRenderer` (`last`) | releases each renderer once the world entity has `Component.Quit` |
| `RenderVulkan.Recipe.Shaders` | compiles the rectangle shaders |

See [rendering.md](rendering.md).

## slop_network_plugin

Replicates components between the environments of one program: state a component declares with
`mirrored_from(environment)`, and messages it declares with `sent_from(environment)`. Connections are entities;
`Network.Component.Listen` or `Network.Component.Connect` on the world entity starts it. The wire is binary frames
encoded by the engine's derived codec. TCP through the library's non-blocking `Socket`. See
[networking.md](networking.md).

## slop_spatial_plugin

A uniform grid over the ground plane, for area of interest, sight and aggro (a proposal by Claude).
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

Observing by distance: `Interest.Component.Viewer` on a connection entity, and the `Equip`, `MarkObserved` and
`Gather` systems that keep `Network.Component.Observer` children on every indexed entity in a viewer's range. It
loads the network and spatial plugins. See [networking.md](networking.md#area-of-interest).

## slop_mongodb_plugin

The engine side of MongoDB. The driver itself (BSON, OP_MSG, `Mongo.Client`, `Mongo.Collection`,
`Mongo.TypedCollection<T>`, the compile-time `Mongo.Codec<T>`) is its own package, `spite_mongodb_driver`, beside
this repository, so programs that are not games use it too. The plugin loads it
(`load "../../../../spite_mongodb_driver@f0c4aea/mongodb"`, a pinned commit) and adds `Mongo.Component.Database` (host, port, database
name) and `Mongo.Component.Client` (a connection pool and the database it names), which `database.connect()` makes;
`Mongo.System.ConnectDatabases` (`input`) adds one beside every database that has none. Running queries as IO systems between frames comes with the compiler's
"does this function wait" (D209).
