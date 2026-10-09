# Conventions

## Folders

Every package, plugin or game uses the same folders, and the folder is the meaning:

| Folder | Namespace | Holds | Found by |
|---|---|---|---|
| `component/` | `Component` | components; an empty file is a marker | name |
| `system/` | `System` | systems | `App()`, every class in a `System` namespace |
| `bundle/` | `Bundle` | spawnable groups of components | name |
| `recipe/` | `Recipe` | recipes | `cookbook.cook()`, every class in a `Recipe` namespace |
| `asset/` | `Asset` | asset formats | name |

An engine plugin lives in `plugins/slop_<feature>_plugin/<feature>/`, so loading it gives the namespace
`<Feature>`; its assets sit in `<feature>/assets/`. A game's swappable plugins (its theme) live beside the program as
`<game>_<feature>_plugin/<feature>/`. See [plugins.md](plugins.md#naming-and-layout). The core is
`slop/`; generic classes (`Column`, `Row`, `Slot`, `Pack`, `Entity`, `World`, ...) sit at its root.

## Names

- Spite's rules apply: `snake_case` names, `PascalCase` classes, no abbreviations, no single letters.
- Spite refuses an operator's function called by name, so engine code writes the operator: `slots[id]` and
  `slots[id] = slot` for a `Dictionary` or a `List`, `matrix.pose = pose` for `set_pose`. A lookup whose answer may
  be missing is kept in a local and narrowed (`var found = known[remote]`, then `assert found`), so the key is read
  once.
- A row type is named after what it describes: `HoveredButton`, `ClickedCounter`, `PendingWindow`.
- A component that exists in more than one dimension carries the dimension in its name, matching the library's
  `Vector2`/`Vector3`: `Position2D` and `Position3D`, not two `Position` classes told apart by namespace. A
  component with only one dimension keeps its plain name until a second one arrives.
- A system is named after what it does: `CountClicks`, `OpenWindow`, `DrawUi`.
- A class name means one class (Spite's rule): no class shares its last name with a standard library class, or
  with a class whose namespace encloses its own. A game's `System.OpenWindow` is refused beside
  `Windows.System.OpenWindow`, and `Input.Component.Key` beside an `Input.Key`, so each is named after what it is:
  `System.SpawnWindow`, `Input.KeyCode`.
- A system's function is named after its phase: `update_each`, `render_all`, `after_input_each`.
- **No other function may end in `_each` or `_all`**: the runner finds phase functions by that suffix, so a helper
  called `drag_all` becomes a phase named `drag`. Name helpers `drag_every`, `interact_pointer`, and so on.

## Rules the engine enforces

- A system has exactly one phase function, and its phase must be one of the engine's.
- State is a component on an entity (program-wide state on `world.entity`). A component holds no `List`,
  `Dictionary` or `Parallel` (a compile error): lists live in resources, singletons outside `component/`
  ([ecs.md](ecs.md#resources)).
- No system declares how it is scheduled or which thread it runs on. A component the operating system ties to one
  thread (a window's handle) declares `pinned_to_creating_thread()`, and every system that touches it runs on the
  thread that created it ([ecs.md](ecs.md#components-pinned-to-a-thread)).
- A component class with no attributes is a marker, and is never fetched.
- A component holding an `Entity` is a link and holds only `var entity = Entity()`; it is added once its entity is
  alive and goes when that entity does ([ecs.md](ecs.md#links-between-entities)). No component, marker or value
  stands for something an entity lacks.

## Memory

Bytes are a `List<Byte>`, read and written by position (`Asset.Bytes` wraps one), and tables are plain lists. Only
the memory a C library hands out or takes (Vulkan structs, the draw list's GPU records, the software canvas) is
touched through `Raw`, `Memory.Heap()` or `ForeignBytes`, and a class that allocates frees in its `drop()`.

## Rules the design follows

- A component holds one fact. State is markers (`Hovered`, `Pressed`); a moment is a component its owner adds and
  removes (`Clicked`); styles are one component per property.
- There are no events and no startup schedule: a system runs when its query matches, and change tracking
  (`Added<T>`, `Removed<T>`) says "just happened".
- A game names assets by id; loading them is the engine's job.
- Nothing is registered: folders, `load` and templates find everything.

---

Next: [Plugins](plugins.md), everything beyond the core and how a program opts into it.
