# SlopEngine

A game engine written in the Spite language: Bevy, with metaprogramming in place of Bevy's type machinery. A
multithreaded ECS, meant to build "the good kind of AI slop" and eventually Theseus (the MMO, client and server). The
main goal right now is to find out whether Spite is ready. What it is missing is in
[INSIGHTS.md](INSIGHTS.md). This file is the overview; [docs/](docs/README.md) documents every part in depth.

Everything runs on Windows with the compiler in `D:\Projects\SpiteLanguage` (`bin/spite`).

## Run it

From `examples/`, where `spite` means `D:/Projects/SpiteLanguage/bin/spite`:

```bash
spite click_counter                          # a Vulkan window with a button that counts its clicks
spite click_counter_test                     # the game, loaded by its test: hidden window, 5 real clicks
spite click_counter_test -- --clicks=12 --show_window=true
spite render_parity --debug-memory           # Vulkan against the software rasteriser, every pixel
spite use_potion --debug-memory              # the potion example from Mortaro's notes
spite healing --debug-memory                 # headless: a parallel stage, entity ids, a report
spite tracking --debug-memory                # Added and Removed, each seen exactly once before and after the change
spite stress --optimized                     # 200k entities, two systems, timings
spite asset_round_trip --debug-memory        # an asset class saved and read back through its derived codec
spite psd_probe                              # buttons.psd read in pure Spite
spite zstd_probe -- --source=<file.blend> --output=<file>   # zstd in pure Spite
spite blend_probe -- --source=<file.blend>   # Blender 5.2 datablocks, SDNA structs, mesh attributes
```

Verified on 2026-09-24: all of them run, every `--debug-memory` run is balanced, and the click test passes for 5 and
12 clicks.

## A program is its entry file

```gdscript
# examples/click_counter/click_counter.spite
var cookbook = Recipes.Cookbook()

func ClickCounter() {
    load "../../slop"
    load "../../plugins/slop_window_plugin"
    load "../../plugins/slop_platform_plugin"
    load "../../plugins/slop_input_plugin"
    load "../../plugins/slop_ui_plugin"
    load "../../plugins/slop_render_plugin"
    load "../../plugins/slop_render_vulkan_plugin"
    load "../click_counter_theme_plugin"
    cookbook.cook()
    var app = App()
    app.run()
}
```

The entry loads and runs, and nothing else: it spawns nothing. The world's first entities come from systems whose
rows say when, like everything else. `System.OpenMainWindow` asks for `Added<Component.Frame>`, which matches once, in
the first tick, because `App()` puts the frame counter on the world entity; `System.SpawnCounter` asks for
`Added<Window.Component.Window>` and builds the UI tree.

There is no plugin list, no composition and no registration:

- **A plugin is opted into by loading its folder.** Swap `render_vulkan` for `render_software` and the game draws
  on the CPU.
- **Every class in a `System` namespace is a system** (D115). `App()` finds them all at compile time with
  `add_system(system: Symbol<System>)`.
- **Every class in a `Recipe` namespace is a recipe.** `cookbook.cook()` finds them the same way, runs their `build()`, and then watches their sources.

## Folders

Every package, plugin or game has the same folders:

| Folder | Namespace | Holds |
|---|---|---|
| `component/` | `Component` | components: plain data classes. A tag is an empty file |
| `system/` | `System` | systems |
| `bundle/` | `Bundle` | classes whose attributes are components, for `world.create_entity_from_bundle` |
| `recipe/` | `Recipe` | recipes: turn source files into assets |
| `asset/` | `Asset` | asset formats: declared classes, with derived binary codecs |

## Systems are query functions

A system's function name says when it runs (D116), and its parameter types are its query (D114):

```gdscript
# examples/use_potion/system/consume_potion.spite
type Potion {
    entity: Entity
    item: Component.HealingItem
    active: Component.Active
    owner: Entity
}

type Target {
    health: Component.Health
    alive: Component.Alive
}

var world = World()

func update_each(potion: Potion, target: Target) {
    target.health = target.health + potion.item.healing_amount
    world.despawn(potion.entity.id)
}
```

- `<phase>_each(rows...)` runs once for every matching combination of rows. `<phase>_each()` with no parameters runs
  once per tick.
- `<phase>_all(rows: List<Row>, ...)` runs once with every match.
- A row is a `type` in the system's file. `Runner<T>` walks its fields with a plural template to decide what to
  query, and fills them from the columns. A replaced component (`target.health = target.health + ...`, through
  `Health.sum`) is written back after the call.
- In a row, an `Entity` field named `entity` is the row's own id. Any other `Entity` field is a relation: `owner` is
  stored as the component `Entity.owner`, and the next row is the entity it points at. (Claude's proposal,
  unconfirmed.)
- There are no resources. State is a component on an entity: program-wide state (`Component.Quit`,
  `Component.Frame`) on the world entity, per-window state (`Input.Component.Mouse`, the draw list, the renderer)
  on the window, reached through rows like any other data. `World` is the only singleton a system holds.
- No system is tied to a thread: windows belong to a dedicated window thread, and structural changes go into a
  per-runner buffer, so any system can run in parallel with any other that shares no component.

The engine's phases, in order:

`input` → `after_input` → `update` → `prepare` → `layout` → `render` → `after_render` → `present` → `last`

Inside a phase, systems run in dotted-name order, and consecutive systems that share no component
class share a stage and run on separate `Parallel` threads. `app.describe()` prints the stages:

```
stage 0 (input): Windows.System.OpenWindow
stage 1 (input): Windows.System.PumpMessages
stage 2 (after_input): Ui.System.Interact
stage 3 (update): ClickTest.System.DriveClicks, System.CountClicks
stage 4 (update): System.SpawnCounter
...
```

## Entities

There is no startup schedule. A system runs when its query matches, so "when the window is created" is part of the
query: `window: Added<Window.Component.Window>` matches it once, in each system that asks.

```gdscript
type NewWindow {
    window: Added<Window.Component.Window>
}

var world = World()

func update_each(_window: NewWindow) {
    var screen = world.create_entity_from_bundle(Bundle.Screen())
    var title = Bundle.Title(screen.id)
    world.create_entity_from_bundle(title)
}
```

| Call | Does |
|---|---|
| `world.create_entity()`, `world.create_entity_from_bundle(bundle)` | a new `Entity`; its `id` is known at once, so children can point at it |
| `entity.add_component(component)` | adds or replaces one component, after the stage |
| `entity.remove_component(Ui.Component.Hovered)` | removes one component, after the stage |
| `entity.remove()` | removes the entity, after the stage |
| `Lookup<Component.Health>().of(id)` | another entity's component, as a `Component.Health?` |

Each runner queues its changes into its own buffer, applied in runner order at the stage boundary, so systems that
change the world still run in parallel and the result doesn't depend on which thread finished first.

### Change tracking instead of events

There are no events, only components. A row can ask for a change:

| Row field | Matches |
|---|---|
| `window: Added<Window.Component.Window>` | components added since this system last ran; `.value` is the component |
| `released: Removed<Ui.Component.Pressed>` | entities that lost the component since this system last ran |

Each column records the tick each row was added, the engine keeps a short log of removals, and each system remembers
when it last ran. So every system sees each change exactly once, wherever it runs relative to the change. The
`tracking` example checks it with one reader before the change and one after.

A component holds one fact. The button is `Ui.Component.Button` (its bounds), plus the marker components
`Ui.Component.Hovered` and `Ui.Component.Pressed` while those are true, and `Ui.Component.Clicked` on the tick a
press is released over it. `Ui.System.Interact` owns all three: it adds `Clicked` on a click and removes it on its
next run, so a system that reacts to a click just asks for it:

```gdscript
type ClickedCounter {
    clicked: Ui.Component.Clicked
    click_count: Component.ClickCount
    label: Ui.Component.Label
}

func update_each(counter: ClickedCounter) {
    counter.click_count.clicks = counter.click_count.clicks + 1
    counter.label.text = "{counter.click_count.clicks}"
}
```

### Styles are components

Each style property is its own component, as if every CSS property were one: `Ui.Component.BackgroundImage
{ texture }` and `Ui.Component.BackgroundColor { color }`. The render plugin paints whatever has them, in tree order
(`Render.System.DrawUi`). The game describes its states as systems, the way
CSS describes `:hover`:

```gdscript
# examples/click_counter_theme_plugin/theme/system/style_hovered_button.spite
type HoveredButton {
    hovered: Added<Ui.Component.Hovered>
    image: Ui.Component.BackgroundImage
    primary: Component.ButtonPrimary
}

func update_each(button: HoveredButton) {
    button.image.texture = "ui.button.primary.hover"
}
```

The click counter has four: `HoveredButton`, `UnhoveredButton`, `PressedButton` and `ReleasedButton`. The click test
checks the button ends on its hover plate.

### Textures are named, the engine loads them

A game only names an asset id. `Render.Component.Textures.request(id)` answers a slot at once and starts a
`Parallel` job that reads its record from the cache binary and decodes it on its own thread; the frame only polls
it. `DrawUi` skips an image until its slot is ready, and the Vulkan backend stages at most 8 MiB of new textures per
frame and records their copies into the frame's own command buffer. Nothing blocks a frame, and nothing in the game
has to know (see docs/performance.md, "No stutters").

**A component with no attributes is a marker, and a marker is only ever a filter.** The engine decides that at
compile time (a plural template over the class finds no attributes). Its column stores membership and ticks but no
values, and a row never fetches it or writes it back. `Hovered`, `Pressed`, `Clicked`, `Alive` and `Active` all cost
one sparse-set entry per entity and nothing else.

"The window was just created" is `Added<Window.Component.Window>`.

When quit is requested, `App` runs one more tick so systems can react. `RenderVulkan.System.ReleaseRenderer` releases
the GPU there.

## Rendering

`Render` fills each draw target's `Render.Component.DrawList`, a list of rectangles in raw memory, each solid or textured (text is one
rectangle per lit cell of a 5x7 font), and a backend turns the list into a frame:

- `RenderSoftware` rasterises it into a canvas, sampling textures and blending straight alpha, and blits it with GDI.
- `RenderVulkan` uploads it as per-instance vertex data and draws it with one instanced draw per run of the same
  texture (one descriptor set per texture, a 1x1 white one for solid rectangles) into an offscreen B8G8R8A8 image, which it blits to the swapchain and presents. It uses Vulkan 1.3 with dynamic rendering, the
  validation layer when not optimized, a mailbox swapchain, and a semaphore per image.

`render_parity` renders the click counter's screen, including the textured button and its alpha edges, through both
and compares every pixel: 0 of 256,000 differ.
Vulkan is called through `DynamicLibrary("vulkan-1.dll", ...)` alone. Its structs are written by
`RenderVulkan.Structure`, which appends fields in declaration order and pads to natural alignment.

The window has no window procedure, because Spite can't pass a callback to C yet. `OpenWindow` registers
`DefWindowProcA` itself, and `PumpMessages` reads mouse messages out of the queue before dispatching them.

## Recipes and assets

A recipe is plain code:

```gdscript
# examples/click_counter_theme_plugin/theme/recipe/ui.spite
var layers = Psd.Layers()

func build() {
    layers.open_in("../click_counter_theme_plugin/theme", "ui.buttons")
    layers.texture("Plates/Primary/Normal", "ui.button.primary.normal")
    layers.texture("Plates/Primary/Hover", "ui.button.primary.hover")
    layers.texture("Plates/Primary/Pressed", "ui.button.primary.pressed")
    layers.skip("Plates/Secondary/", "click_counter has one button, and it is primary")
    layers.skip("Close/", "click_counter has no window to close")
    layers.finish()
}
```

A step writes an asset by id into `<program>/.slop-cache/` and skips itself when its input's fingerprint hasn't
changed. `finish()` refuses a layer nothing claimed. Any package can bring recipes along with its systems.

An asset format is a declared class. `Pack<T>` derives its binary codec from its attributes (numbers, `Boolean`, text,
lists and nested classes), so no format has a hand-written reader:

```gdscript
# slop/asset/texture.spite
var width = 0
var height = 0
var pixels = List<Integer>()
```

## Loaders in pure Spite

No installed software is needed to read a source file. Each loader is a plugin; `slop/` itself knows only the assets
it contributes ([docs/loaders.md](docs/loaders.md)):

| Loader | State |
|---|---|
| `Psd.Document`, `Psd.Layers` | 8-bit RGB, raw and PackBits, groups, masks. **Bit-exact** with a reference decoder on `buttons.psd` |
| `Zstd.Decoder` | RFC 8878. **Byte-identical** with Zig's std decoder on a 261 MB `.blend`, in 0.86 s |
| `Blend.File`, `Blend.View` | Blender 5.2 (`BLENDER17-01`): blocks, SDNA, any field by name, pointers, `AttributeStorage` |
| meshes, normals, skeletons, skins, animations, packed PNG textures from `.blend` | not built yet: next |
| GLSL to SPIR-V | still `glslangValidator` from the Vulkan SDK: the one tool dependency left |

## Layout

```
slop/                     the core, loaded by every program
  app.spite               App: discovers systems, builds phase-ordered stages, ticks
  runner.spite            Runner<system>: its phase, its accesses, run_each and run_all
  row.spite               Row<type>: one query row's columns, matching, filling and writing back
  column.spite, columns.spite, slot.spite    component storage: sparse sets in raw Memory
  spawn.spite, insert.spite, remove.spite, lookup.spite, entity.spite
  world.spite             World: entity ids, the world entity, queued changes
  component/              Component.Quit, Component.Frame (on the world entity)
  system/                 System.CountFrames
  cook.spite, cooking.spite   Cook: runs every Recipe
  pack.spite, field.spite, list_field.spite   the derived asset codec
  asset/                  Asset.Bytes, Asset.Texture
  recipes/                Recipes.Cache, Recipes.Glsl
plugins/                  each loaded on its own: plugins/slop_<feature>_plugin/<feature>/{component,system,assets,...}
  window/, input/, ui/, render/, render_software/, render_vulkan/
  network/                replicated components and connections (docs/networking.md)
  transform/, camera/, scene/, scene_vulkan/, animation/, lighting/   3D (docs/scene.md)
  mongodb/                the ECS side of MongoDB; the driver is its own package, spite_mongodb_driver
  png/                    PNG decoding
  psd/, zstd/, blend/     the source-format loaders, loaded by whoever has a recipe that reads them
                          (window: component/window, bundle/window, system/open_window, pump_messages;
                           ui: component/button, label, text, hovered, pressed; system/interact)
examples/
  click_counter/          the game
  click_counter_online/   the same game with a server-authoritative counter: client, server and bot environments
  click_counter_test/     its test: a program that loads the game and adds its own systems
  render_parity/, use_potion/, healing/, stress/, asset_round_trip/, psd_probe/, zstd_probe/, blend_probe/
```

## Status

| | |
|---|---|
| Systems as phase functions over `type` rows, found by folder, no registration | built |
| Relations between rows (`owner: Entity`) | built for the `use_potion` shape |
| Stages by class conflicts, `Parallel` per system | built; 1.2x on two systems |
| Window, mouse, button interaction, bitmap text | built, Windows only |
| Vulkan and software backends with pixel parity | built |
| Recipes as code, assets as declared classes, PSD, zstd, `.blend` structure | built |
| Read-only and filter-only access, per-environment builds | not built: need compile-time reads and writes |
| Blender meshes, skeletons, skins, animations, textures | not built: next |
| Thread pool, parallel iteration inside one system | not built |

## Numbers

`spite stress --optimized`: 200,000 entities, `Move` and `Regenerate` in one stage.

| | average tick |
|---|---|
| first version | 302 ms parallel, 422 ms sequential |
| headers cached per system | 128 ms parallel, 133 ms sequential |
| generic singletons real, singletons not reference counted, `type` rows | 65 ms parallel, 81 ms sequential |

About 200 ns per entity per system: better, and still two orders of magnitude from a native ECS. INSIGHTS.md says
where the rest goes.
