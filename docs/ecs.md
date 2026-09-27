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
| `world.create_entity_from_bundle(bundle)` | a new `Entity` with a copy of every component the bundle holds (an `Entity` attribute becomes a relation named after it), so one bundle can be spawned any number of times as a prefab | components after the current stage |
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

Spawning a bundle is one typed command per entity: the attribute walk is written at compile time for each class in a
`bundle/` folder, and every component goes straight into its column, deep-copied. `stress` spawns 200,000 bodies of
four components in about 190 ms (it was about 600 ms through run-time reflection); most of what is left is a
singleton guard per column call, which the language is removing.


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

Replacing a component in the row (`target.health = target.health + ...`) is written back after the call.

### Relations at any moment

A relation is a component, so it can be set or removed whenever an entity's components can (Mortaro, 2026-09-27;
the names below are proposals). The change is queued like any other and applied after the stage.

| Call | Does |
|---|---|
| `entity.add_parent_entity(parent)` | sets the relation `parent`, replacing any earlier one |
| `parent.add_child_entity(child)` | the same, from the parent's side |
| `entity.remove_parent_entity()` | removes the relation `parent` |
| `entity.relate(name, target)`, `entity.unrelate(name)` | any named relation: `target` for a chase, `owner`, `carrier` |

Despawning an entity despawns its children too, and theirs, in the same flush: every entity whose `parent` relation
points at it. Only `parent` cascades; a named relation such as `target` is simply left pointing at nothing.

A row asks for a relation with a field of that name (`parent: Entity`), and the next row is the entity it points at.
A system over two such rows follows the relation instead of pairing every entity of one row with every entity of the
other: `relations_check` sums 10,000 items into the 1,000 players that hold them in 4.4 ms a tick (optimized),
then moves some to another player and drops others, and the sums follow; despawning a player despawns the items it
holds and what they hold.

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
| `app.run()` | ticks at a fixed rate, one tick every `frame_milliseconds` (16; a server sets 50 for 20 Hz), until the world's `Component.Quit.requested`, then ticks once more so systems can react to quitting. The pace is kept against the monotonic clock, so a tick's own time does not add up to drift; a tick that overruns is followed at once, without trying to catch up |
| `app.begin_pacing()`, `app.wait_for_next_tick()` | the two halves of that pacing, for a program that drives its own loop |
| `app.tick()` | one tick: every stage in order, changes applied after each |
| `app.parallel = false` | runs every stage's systems one after another |
| `app.describe()` | the stages, as text |

## Timers

`Component.Timer` is a timer as a component (a proposal by Claude): `timer.start(milliseconds, repeating)`, then the
engine's `RingTimers` system counts it down by the fixed step every tick, in `input`, and sets `timer.rang` on the tick
it reaches zero. A repeating timer starts over, a one-shot one stops. A system reacts by asking for the timer in its
row and checking `rang`:

```gdscript
type Attacking {
    timer: Component.Timer
    monster: Component.Monster
}

func update_each(attacking: Attacking) {
    assert attacking.timer.rang
    attacking.monster.attacks = attacking.monster.attacks + 1
}
```

The step is `Tick().step_milliseconds`, which the app sets from `frame_milliseconds`. The timer is stored inline,
so counting down 10,000 timers costs about 0.26 ms a tick. `timers_check` tests it: a 50 ms repeating timer rings 6
times in 30 ticks of 10 ms and a 120 ms one-shot rings once, and 40 paced ticks of 25 ms take 1,012 ms.

## Storage

Each component class has a column: a sparse set whose bookkeeping lives in raw `Memory`, found by its dotted class
name through `Columns`. The raw header holds the entity of each row, the tick each row was added, and a sparse
array from entity to row. `Column<T>` holds the values themselves. Removal swaps the last row into the gap.
`Column<T>`, `Slot<T>` and `Row<T>` are generic singletons, one per type, so a system's fill is typed code with no
lookup by name on the hot path. Only `Entity` relation columns (`Entity.owner`) look up their name, since they
share one `Column<Entity>` and keep one list per relation.

Values are stored one of two ways:

- **By reference** (the default): a `List<T>`. A system's row holds the stored object, so writing a field changes
  the component.
- **Inline** (proposal by Claude, for Mortaro to decide): a component that declares
  `func stored_inline(): Boolean { return true }` and fits a `Vector` (numbers, `Boolean`, enums, `String`) is
  kept in an `Items<T>` (D218), contiguous in memory.

A system with one row and no `Added`, `Removed` or relation field runs on the fast path, `Stream<System, Row>`. It
walks the driver column and fills each row straight from the columns (D217): inline items are borrowed and written
in place, with no copy and no reference counting, and references are handed over as they are. The runner picks
it with `phase.argument_count() == 1` (D219), so systems with several rows still compile and use the combination
path. Other rows get a copy of inline items, which is written back after the system runs.

A `_all` system's rows are written back after it runs, like a single row's, so writing a field of an inline
component in a list sticks. The opt-in goes away (Mortaro, 2026-09-27: the engine should work this out, not the
game): once a `Lookup` result can lend the stored item instead of a copy (D230, being built), every component that
fits a `Vector` is stored inline with nothing declared.

## IO systems

A system whose phase function can reach a wait (a socket or file read, a sleep, a database call) is an **IO system**,
found at compile time (`$system_type.function_waits`, D209). Nothing marks it; writing straight-line code is enough:

```gdscript
func update_each(pending: Pending) {
    var accounts = database.collection("accounts")
    var found = accounts.find_one(filter)
    ...
}
```

- It never runs inside a stage. Each matching row is copied into a queue during the stage, and after the tick the
  app starts up to eight `Concurrent` workers per system on the main thread; the scheduler resumes them only
  between frames (`Scheduler().resume_only_when_asked()` and `run_ready()` at the end of `App.tick()`), so a
  database round trip never blocks a frame and never interleaves with a stage.
- **Its row is a snapshot.** It runs after its frame, when the components may have moved or gone, so it changes the
  world through commands (`entity.add_component(...)`, `world.despawn(...)`), which apply at the next flush.
- A system with several rows queues each matching combination.

Because the compiler finds every function that can wait, it also catches file reads on the frame path, which the
no-stutter rule forbids: asset lookups go through `Recipes.Catalog`, which loads the cache index on the pool, and
shaders through `Recipes.Blobs`. `examples/io_systems` runs three MongoDB lookups with a 200 ms wait each while
frames keep ticking.
