# The ECS

SlopEngine is Bevy's model, written with Spite's metaprogramming: components are plain classes, systems are
functions whose parameter types are their queries, and everything that would be registration in another engine is
found by the compiler instead.

## Entities

An entity is an `Integer` id, handed out by `World` and wrapped in an `Entity`. Ids are not reused. The world is an entity
too: `world.as_entity()` carries the program-wide components (see [State is components](#state-is-components)).

| Call | Does | When |
|---|---|---|
| `world.create_entity()` | a new `Entity` with no components; its `id` is known at once | now |
| `world.create_entity_from_bundle(bundle)` | a new `Entity` with every component the bundle holds (an `Entity` attribute becomes a relation named after it) | components after the current stage |
| `entity.add_component(component)` | adds a component, or replaces the one of that class | after the current stage |
| `entity.remove_component(Ui.Component.Hovered)` | removes one component; the class itself is the argument | after the current stage |
| `entity.remove()` | removes the entity and all its components | after the current stage |
| `world.as_entity()` | the world entity, which carries program-wide components | now |
| `Lookup<Component.Health>().of(id)` | another entity's component, as a `Component.Health?` | now |
| `Lookup<Component.Health>().has(id)` | whether it has one | now |

A row's `entity: Entity` field is an `Entity`, so a system writes `row.entity.add_component(marker)`; with only an id,
`Entity(id)` makes one. There are no generics in this API (D123): `add_component` takes `Anything` (an empty
`type`, which any class fits), and the class test `if value == $component_type` inside each column narrows it back.
Every class in a `Component` namespace gets its column when `App()` starts, found at compile time the way systems
are. A component built in place goes into a named `var` first, since Spite allows a constructor as an argument only
one level deep.

Changes are applied between stages, like Bevy's `Commands`, so a column never changes while a system is iterating
it. **Each runner has its own command buffer**: before a system runs, its thread is marked with the runner's buffer (a
`ThreadLocal<Integer>`), so `add_component` from systems running in parallel
never contends, and the buffers are applied in runner order at the stage boundary, so the result is the same
whichever thread finished first. New ids come from one counter behind a `Lock`. A system that changes the world
no longer needs a stage of its own.

## Components

A component is a class in a `component/` folder. It holds one fact.

```gdscript
# examples/click_counter/component/click_count.spite
var clicks = 0
```

A component may have functions; `Component.Health` in `use_potion` has `sum`, so `health + amount` gives a new
health.

### Markers

A component with no attributes is a marker: an empty file, such as `Ui.Component.Hovered`. The engine finds this at
compile time (a plural template over the class finds nothing), and a marker is only ever a filter:

- its column stores which entities have it and when each got it, and no values;
- a row never fetches it and never writes it back.

`Hovered`, `Pressed`, `Clicked`, `Alive` and `Active` cost one sparse-set entry per entity.

## Bundles

A bundle is a class in a `bundle/` folder whose attributes are components, with a constructor that sets them up.
`world.create_entity_from_bundle(bundle)` adds each attribute, walked at run time through `attribute.value`, so a
bundle has no code for spawning itself.

```gdscript
# examples/click_counter/bundle/count_label.spite
var parent = Ui.Component.Parent()
var text = Ui.Component.Text()
var label = Component.CountLabel()

func CountLabel(button: Integer) {
    parent.entity = button
    text.text = "0"
    text.scale = 3
}
```

## State is components

There are no resources (Mortaro, 2026-09-25): "Resources shouldnt exist, its just a entity that is only used once
instead, if we want to use it we query for that entity." State that another engine keeps in a resource is a
component on an entity, and a system reaches it through a row like any other data.

- **Program-wide state lives on the world entity.** `App()` puts the core's two there:

  | Component | Holds |
  |---|---|
  | `Component.Quit` | `requested`: the app ends after the tick where it becomes true, plus one final tick |
  | `Component.Frame` | `count`, the number of finished ticks (kept by `System.CountFrames`) |

  A program adds its own with `world.as_entity().add_component(...)`: the tracking example's `Component.Tally`.
- **Per-window state lives on the window entity**: `Input.Component.Mouse` (in the window bundle), and the draw
  list, clear colour, texture cache, software canvas and Vulkan renderer, which the render plugins add when
  `Added<Window.Component.Window>` matches. So several windows each get their own.
- **Services that are not world state are plain classes**: `Render.Font`, `Recipes.Cache`.

`World` is the only singleton the engine has: `var world = World()` at the top of a file.

A row that matches one entity costs nothing extra: a system that takes `(button: Pressable, pointer: Pointer)`
runs once per button, with the window's mouse in `pointer`.

## Systems

A system is a class in a `system/` folder. `App()` finds every class in a namespace ending in `System` at compile
time (D115) and wraps each in a `Runner<TheSystem>` generated for it.

A system has one function, and its name says when it runs and how (D116):

- `<phase>_each(row: Row, ...)` runs once for every matching combination of rows;
- `<phase>_each()`, with no parameters, runs once per tick;
- `<phase>_all(rows: List<Row>, ...)` runs once with every match.

A row is a `type` declared in the system's file; its fields are what the system queries (D114). The runner walks the
fields with a plural template, so nothing is declared twice.

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

### What a row field can be

| Field | Means |
|---|---|
| a component class | the entity must have it; the field is the stored component, and changing its fields changes it |
| a marker component | the entity must have it; nothing is fetched |
| `entity: Entity` (named `entity`) | the entity's own id; not a filter |
| any other `Entity` field, e.g. `owner: Entity` | a relation: stored as the component `Entity.owner`, and the next row is the entity it points at |
| `Added<T>` | `T` was added since this system last ran; `.value` is the component |
| `Removed<T>` | `T` was removed since this system last ran |

Replacing a component in the row (`target.health = target.health + ...`) is written back after the call. Relations
are Claude's proposal, unconfirmed.

### What decides where a system runs

Nothing in a system says how it is scheduled; the runner derives it at compile time:

- **what it touches**: the component classes in its rows. Systems that share none can run at the same time.
- **no thread affinity**: every system can run on any thread. Win32 delivers a window's messages only to the thread
  that created it, so windows belong to a dedicated window thread (`Windows.Owner`), not to any system; systems
  request windows and read input from it through a lock-guarded buffer in raw memory. Vulkan has no thread
  affinity at all.
- **changing the world** costs nothing in scheduling: each runner queues into its own buffer (above).

## Freeing

Removing a component (by `Remove` or a despawn) takes it out of its column at once, so no query or lookup sees it
again; the object itself moves to its column's buried buffer and is freed later, at most `app.release_budget`
(4,096) objects per tick, so unloading a region never frees everything in one frame. A component's `drop()` runs
then, not at the removal.

## Change tracking

There are no events. Every column records the tick at which each row was added, the core keeps a short log of
removals per column (in raw memory: a tick-ordered log, and a per-entity stamp of its last removal), and each system
remembers the tick at which it last ran. So `Added<T>` and `Removed<T>` match each change
exactly once for every system that asks, wherever it runs relative to the change: a system after the change sees it
in the same tick, one before it sees it in the next. Removal records are trimmed after two ticks.

A condition that is a moment rather than a state is still a component with an owner. `Ui.Component.Clicked` is added
by `Ui.System.Interact` on the tick a press is released over the button and removed by it on its next run.

## Phases and stages

The engine owns the phases, in order:

`input` → `after_input` → `update` → `prepare` → `layout` → `render` → `after_render` → `present` → `last`

Inside a phase, systems run in the order of their dotted names. Consecutive systems that share no component class
form a stage, and a stage's systems run on separate `Parallel` threads, the last of them on the calling thread. A system holding `World` always has a stage of its own. Queued
changes are applied after each stage. `app.describe()` prints the stages:

```
stage 0 (input): Windows.System.OpenWindow
stage 1 (input): Windows.System.PumpMessages
stage 2 (after_input): Ui.System.Interact
...
```

Ordering inside a phase is by name, not by data. The finer phase names carry the ordering that matters today.

## The app

| Call | Does |
|---|---|
| `App()` | finds every system, builds the stages |
| `app.run()` | ticks until the world's `Component.Quit.requested`, sleeping `frame_milliseconds` (16) between ticks, then ticks once more so systems can react to quitting |
| `app.tick()` | one tick: every stage in order, changes applied after each |
| `app.parallel = false` | runs every stage's systems one after another |
| `app.describe()` | the stages, as text |

## Storage

Each component class has a column: a sparse set in raw `Memory`, found by its dotted class name through
`Columns`. A column holds the values (8-byte references, retained), the entity of each row, the tick each row was
added, and a sparse array from entity to row. Removal swaps the last row into the gap. Markers skip the values.
`Column<T>`, `Slot<T>` and `Row<T>` are generic singletons, one per type, so a system's fill is typed code with no
lookup by name on the hot path.
