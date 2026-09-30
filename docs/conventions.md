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
- A row type is named after what it describes: `HoveredButton`, `ClickedCounter`, `PendingWindow`.
- A system is named after what it does: `CountClicks`, `OpenWindow`, `DrawUi`.
- A system's function is named after its phase: `update_each`, `render_all`, `after_input_each`.
- **No other function may end in `_each` or `_all`**: the runner finds phase functions by that suffix, so a helper
  called `drag_all` becomes a phase named `drag`. Name helpers `drag_every`, `interact_pointer`, and so on.

## Rules the engine enforces

- A system has exactly one phase function, and its phase must be one of the engine's.
- There are no resources: state is a component on an entity (program-wide state on `world.entity`), and `World`
  is the only singleton a system holds.
- No system has thread affinity. Something the OS ties to one thread (a window's message queue) gets a thread of
  its own that owns it, and systems talk to that thread through a lock-guarded buffer.
- A component class with no attributes is a marker, and is never fetched.
- A component holding an `Entity` is a link and holds only `var entity = Entity()`; it is added once its entity is
  alive and goes when that entity does ([ecs.md](ecs.md#links-between-entities)). No component, marker or value
  stands for something an entity lacks.

## Memory

Program code never reads raw addresses (D178: only the standard library may). SlopEngine's raw-memory structures
(columns, the draw list, Vulkan structs, the cache files) go through `Raw` (`raw.read_long(address, offset)` and
friends, built on `TypedMemory<T>`), and allocate with `var heap = Memory.Heap()` (`allocate`, `resize`, `free`).
A class that allocates frees in its `drop()`, and never reads a byte it didn't write: `resize` doesn't clear.

## Rules the design follows

- A component holds one fact. State is markers (`Hovered`, `Pressed`); a moment is a component its owner adds and
  removes (`Clicked`); styles are one component per property.
- There are no events and no startup schedule: a system runs when its query matches, and change tracking
  (`Added<T>`, `Removed<T>`) says "just happened".
- A game names assets by id; loading them is the engine's job.
- Nothing is registered: folders, `load` and templates find everything.
