# The ECS

SlopEngine is Bevy's model, written with Spite's metaprogramming: components are plain classes, systems are
functions whose parameter types are their queries, and everything that would be registration in another engine is
found by the compiler instead.

## Entities

An entity is an `Integer` id, handed out by `World` and wrapped in an `Entity`. Ids are not reused. The world is an entity
too: `world.as_entity()` carries the program-wide components (see [State is components](#state-is-components)).
`Entity()` is an entity not set yet, which a [link component](#links-between-entities) declares as its default; it is
never added, looked up or used.

| Call | Does | When |
|---|---|---|
| `world.spawn_entity()` | a new `Entity` with no components; its `id` is known at once | now |
| `entity.spawn_entity()` | a new `Entity` that is a child of `entity`: it gets `Component.Parent` naming `entity`, so it is despawned with it | now; the `Parent` after the current stage |
| `world.spawn_entity_from_bundle(bundle)` | a new `Entity` with a copy of every component the bundle holds, so one bundle can be spawned any number of times as a prefab | components after the current stage |
| `world.entity_of(id)` | the `Entity` of an id a program kept as an `Integer`; a negative id crashes (`an_entity_id_is_zero_or_more`) | now |
| `entity.add_component(component)` | adds a component, or replaces the one of that class | after the current stage |
| `entity.remove_component(Ui.Component.Hovered)` | removes one component; the class itself is the argument | after the current stage |
| `entity.remove()` | removes the entity and all its components | after the current stage |
| `world.as_entity()` | the world entity, which carries program-wide components | now |
| `Lookup<Component.Health>().of(id)` | another entity's component, as a `Component.Health?` | now |
| `Lookup<Component.Health>().has(id)` | whether it has one | now |

A row's `entity: Entity` field is an `Entity`, so a system writes `row.entity.add_component(marker)`; with only an id,
`world.entity_of(id)` makes one (a proposal by Claude: Spite has neither overloading nor visibility narrower than a
class, so there is no constructor taking an id that only the engine may call; `Entity`'s `set_id` refuses a negative
id instead, and every entity call crashes on an `Entity()` not set yet, `an_entity_is_set_before_it_is_used`). There
are no generics in this API (D123): `add_component` takes `Anything` (an empty
`type`, which any class fits), and the class test `if value == $component_type` inside each column narrows it back.
Every class in a `Component` namespace gets its column when `App()` starts, found at compile time the way systems
are. A component built in place goes into a named `var` first, since Spite allows a constructor as an argument only
one level deep.

A negative id is no entity, so `of` and `has` crash on one (`looked_up_a_real_entity_not_a_negative_id`) instead of
reading outside the column, which once segfaulted Theseus. An optional link is a component that is present or
absent, never an id of −1.

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

### Components hold data

Information goes into components, implementation into systems (Mortaro, 2026-09-30). State is a marker because a
marker is a public fact other code can query and combine: a specialised library can ask for `Render.Component.Texture`
and `Component.Loading` to drive its own loading screen without touching the texture system. So the markers a system
adds are plain, reusable ones (`Loading`, `JustPressed`), never something private to that system.

A component that is not in use is removed; a field never says "inactive" (Mortaro, 2026-09-28). So a component may
not have:

- a `Boolean` attribute: a state is a marker, added when it holds and removed when it does not (`Component.Quit`,
  `Component.Rang`, `Window.Component.Hidden`, `Input.Component.LeftDown`);
- an `Entity` attribute beside other attributes: a component holding an `Entity` is a
  [link component](#links-between-entities), which holds only `var entity = Entity()`;
- an optional `T?` attribute: whether the value is there is another component;
- a `List` or a `Dictionary` (Mortaro, 2026-09-30), **a compile error**: parallel lists indexed by an id become one
  entity per item with its own components (each texture, mesh, terrain material and font size is an entity), a list
  of entity ids becomes a link component on each item's entity (an observation names its connection with
  `Network.Component.Observer`), a list of states becomes a marker on each item (`Input.Component.JustPressed` on a
  held key's entity), and the entity's own variable data is either entities (input events, held keys, gamepad
  buttons) or asset data held by an object (a model's `Scene.Pose`, an atlas's `Ui.GlyphTable`, a grid template's
  CSS text). Lists live only in [resources](#resources);
- a `Parallel` (Mortaro, 2026-09-30, resolving Theseus A99), **a compile error**: an entity with a job in flight has
  the marker `Component.Loading` (or another public marker, such as `Network.Component.Dialing`), added when the job
  starts and removed when its result lands, and the `Parallel` itself lives with whoever started it, in a resource
  keyed by the entity (`Render.Textures`, `Scene.Meshes`, `Network.Dials`);
- a `stored_inline()` function: storage is inferred.

The `List`, `Dictionary` and `Parallel` rules are checked while compiling: `ComponentRule` makes an
`AttributeRule<Component, attribute class>` for every attribute, whose `crash $attribute_type != List` (and the
other two) folds to false for a breaking attribute, which Spite reports as a compile error naming the instance, for
example `'crash $attribute_type != List' always halts in AttributeRule<Bag, List<Integer>>` in
`a_component_holds_no_list`. `examples/list_component_refused/test.sh` checks all three. A `Parallel` is recognised by
its `finished_value` function, since `$T == Parallel` does not name a kind the way `List` and `Dictionary` do.

The other rules are checked at startup: `App()` walks every registered component (`slop/component_rule.spite`),
prints each break as `ECS rule: <Component>.<attribute> ...`, then crashes on `components_follow_the_ecs_rules` if
there was any. For an `Entity` attribute it also reports one not named `entity`, and a default naming a real entity
instead of `Entity()`. An `Integer` holding an entity id cannot be told from any other number, so no rule catches
one: an entity a component keeps is a link, never an `Integer` field (the last ones, `Viewer.entity`,
`Observer.subject`/`observer`, `Sender.connection` and `Connect.connection`, are links now).

A component marks only what an entity has, never what it lacks (Mortaro, 2026-09-30): no field, marker or value
says "none", "not yet" or "no target". An entity with nothing to chase has no `Target`.

### Links between entities

A link is an ordinary component whose one attribute is the entity it names, in a file of its own (Mortaro,
2026-09-30):

```gdscript
# slop/component/parent.spite
var entity = Entity()
```

`Component.Parent`, a game's `Target`, `Source`, `Owner` or `Near` all have this shape. Anything else about the link
goes in a component of its own on the same entity, and a link that carries data is an entity of its own: a hit is
an entity holding `Source`, `Target` and `Hit { damage }`, so several hits in one frame are several entities. A
component holding an `Entity` and anything else is an ECS rule break at startup.

`Entity()` is only the declared default, because Spite gives every attribute one. A link is added when its entity is
known, like any component, and never before:

```gdscript
var chase = Component.Target()
chase.entity = prey
hunter.add_component(chase)
```

- **Adding a link whose entity is not set, or is already despawned, crashes** when the command applies
  (`a_link_is_added_only_once_its_entity_is_set`, `a_link_names_a_living_entity`), whether it came from
  `add_component`, a bundle or the network. `examples/dead_link_refused/test.sh` checks both.
- **A link's entity is always alive.** When an entity is despawned, every link naming it goes in the same flush:
  a `Parent`'s holder is despawned with it (and its children, and theirs); any other link component is removed
  from its holder, which stays. The removal is an ordinary one, so `Removed<Component.Target>` sees it and a
  mirrored link vanishes on every peer. So a system never checks whether its target still exists.
- The links are found at compile time: `App()` registers every component class holding an `Entity`, and the despawn
  flush walks only those columns, reading each row's entity where it is stored. It costs one pass over the link
  rows for each flush that despawns something, plus one more pass over `Parent` per level of children (a proposal
  by Claude, chosen over a reverse index from entity to holders, which a system writing a link's entity in place
  would silently leave stale).

Changing a link is adding it again (`add_component` replaces), and removing it is `remove_component`. Links are
networked like any component: `mirrored_from` or `sent_from` on the link's class, and its entity travels as the
receiver's own ([networking.md](networking.md#entity-fields-travel-as-the-receivers-entities)).

## Bundles

Spawning a bundle copies each of its components, so one bundle can be spawned any number of times. The fast way is
one typed command per entity, with the attribute walk written at compile time for each class in a `bundle/` folder:
`stress` spawned 200,000 bodies of four components in about 190 ms that way, against about 650 ms through run-time
reflection. Which bundle class a value is cannot yet be asked reliably at run time (both forms are language bugs,
D237), so a bundle the typed path does not recognise takes the reflective path, which is correct, and slower.


A bundle is a class in a `bundle/` folder whose attributes are components, with a constructor that sets them up.
`world.spawn_entity_from_bundle(bundle)` adds each attribute, walked at run time through `attribute.value`, so a
bundle has no code for spawning itself.

```gdscript
# examples/click_counter/bundle/count_label.spite
var parent = Component.Parent()
var text = Ui.Component.Text()
var label = Component.CountLabel()

func CountLabel(button: Entity) {
    parent.entity = button
    text.text = "0"
    text.scale = 3
}
```

## State is components

State that another engine keeps in a resource is a component on an entity (Mortaro, 2026-09-25: "Resources
shouldnt exist, its just a entity that is only used once instead, if we want to use it we query for that entity"),
and a system reaches it through a row like any other data.

- **Program-wide state lives on the world entity.** `App()` puts the core's two there:

  | Component | Holds |
  |---|---|
  | `Component.Frame` | `count`, the number of finished ticks (kept by `System.CountFrames`), and `step_milliseconds`, this tick's step |

  Quitting is a marker: a system that ends the program adds `Component.Quit` to the world entity, and the app ends
  after that tick, plus one final tick. A row that should stop once quitting asks for `Without<Component.Quit>`.

  A program adds its own with `world.as_entity().add_component(...)`: the tracking example's `Component.Tally`.
- **Per-window state lives on the window entity**: `Input.Component.Mouse` (in the window bundle), and the draw
  list, clear colour, software canvas and Vulkan swapchain, which the render plugins add when
  `Added<Window.Component.Window>` matches. So several windows each get their own.
- **Services that are not world state are plain classes**: `Render.Font`, `Recipes.Cache`.

### Resources

Since components hold no lists (above), what is a list by nature lives in a **resource**: a singleton class outside
`component/`, bound like any singleton (`var textures = Render.Textures()` at the top of a system's file). A resource
holds indexes and bookkeeping, never the items themselves, which are entities:

| Resource | Holds |
|---|---|
| `Render.Textures`, `Scene.Meshes`, `Scene.TerrainMaterials` | asset id to slot, each slot's entity, and the load jobs in flight keyed by entity |
| `Ui.Fonts` | the loaded font faces by name, and each size's atlas entity |
| `Scene.Draws`, `Scene.Lights` | this frame's draws and palettes per view, and the gathered lights (scratch, rebuilt each frame) |
| `RenderVulkan.Renderer`, `SceneVulkan.MeshRenderer` | the Vulkan device, pipelines and per-frame GPU buffers |
| `Network.Dials` | the dial jobs in flight, keyed by the entity marked `Dialing` |

A system that binds a resource names it in what it touches, so two systems binding the same one never share a stage
(the runner counts every singleton a system holds, `World` aside). Choosing a resource over entities is a proposal by
Claude case by case, noted where each is documented.

`World` is the engine's central singleton: `var world = World()` at the top of a file.

A row that matches one entity costs nothing extra: a system that takes `(button: Pressable, pointer: Pointer)`
runs once per button, with the window's mouse in `pointer`.

## Systems

A system is a class in a `system/` folder. `App()` finds every class in a namespace ending in `System` at compile
time (D115) and wraps each in a `Runner<TheSystem>` generated for it.

A system has one function, and its name says when it runs and how (D116):

- `<phase>_each(row: Row, ...)` runs once for every matching combination of rows;
- `<phase>_each()`, with no parameters, runs once per tick;
- `<phase>_all(rows: List<Row>, ...)` runs once with every match, **unless its first list is empty**: then it does
  not run and none of its lists is built (Mortaro, 2026-09-27: the fastest way to skip idle work). The first list is
  the system's subject and the rest are context, so a system that must run on every tick puts something always
  present first (render targets, tallies), and a system that acts only now and then puts its trigger first, for
  example a marker added on the ticks it should act.

A row is a `type` declared in the system's file; its fields are what the system queries (D114). The runner walks the
fields with a plural template, so nothing is declared twice.

```gdscript
# examples/use_potion/system/consume_potion.spite
type Potion {
    entity: Entity
    item: Component.HealingItem
    active: Component.Active
    owner: Component.Owner
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
| `entity: Entity` (named `entity`) | the entity's own id; not a filter. Each row gets an `Entity` of its own, so storing it in a link (`chase.entity = prey.entity`) keeps naming that entity after the runner moves on (it once named whichever entity the runner filled next). An `Entity` field with any other name is a startup crash, `a_row_field_of_class_entity_is_named_entity` |
| a link component, e.g. `parent: Component.Parent` | the entity must have it, like any component; in a system's first row it also says the next row is the entity it names ([below](#following-a-link)) |
| `Added<T>` | `T` was added since this system last ran; `.value` is the component |
| `Removed<T>` | `T` was removed (or its entity despawned) since this system last ran; the component itself is gone, so there is no `.value` to read |
| `Without<T>` | the entity does not have `T`: a system skips entities in a state by the absence of a component, never by a flag in a field (name the field without a leading `_`, since private fields are not walked) |

Replacing a component in the row (`target.health = target.health + ...`) is written back after the call.

### Following a link

A row asks for a link by holding the link component, and in a system of two rows, a link in the first row makes the
second row the entity it names (a proposal by Claude: the first link component of the first row is followed):

```gdscript
# examples/relations_check/system/sum_held.spite
type Held {
    item: Component.Item
    parent: Component.Parent
}

type Owner {
    player: Component.Player
}

func update_each(held: Held, owner: Owner) {
    owner.player.total = owner.player.total + held.item.value
}
```

So the system follows the link instead of pairing every entity of one row with every entity of the other:
`relations_check` sums 10,000 items into the 1,000 players that hold them in 3.3 ms a tick (optimized), then moves
some to another player (`add_component` of a new `Parent`) and takes others out (`remove_component`), and the sums
follow; despawning a player despawns the items it holds and what they hold, and despawning a hunter's prey removes
its `Target` in that flush, which a `Removed<Component.Target>` row sees.

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
| `app.run()` | ticks at a fixed rate, one tick every `frame_milliseconds` (16; a server sets 50 for 20 Hz), until the world entity has `Component.Quit`, then ticks once more so systems can react to quitting. The pace is kept against the monotonic clock, so a tick's own time does not add up to drift; a tick that overruns is followed at once, and the next step is the time that really passed, so the game runs in real time whatever the frame rate |
| `app.begin_pacing()`, `app.wait_for_next_tick()` | the two halves of that pacing, for a program that drives its own loop |
| `app.tick()` | one tick: every stage in order, changes applied after each |
| `app.parallel = false` | runs every stage's systems one after another |
| `app.describe()` | the stages, as text |

## Timers

`Component.Timer` is a timer as a component (a proposal by Claude): `timer.start(milliseconds)`, then the engine's
`RingTimers` system counts it down by the step every tick, in `input`, and adds the marker `Component.Rang` to the
entity on the tick it reaches zero; `SilenceTimers` removes it in `last`, so every system of that tick sees it and
none of the next. A timer with the marker `Component.Repeating` starts
over; a one-shot timer is removed once it rings. A system reacts by asking for `Rang` in its row, so it runs only on
the ticks a timer rang:

```gdscript
type Attacking {
    rang: Component.Rang
    monster: Component.Monster
}

func update_each(attacking: Attacking) {
    attacking.monster.attacks = attacking.monster.attacks + 1
}
```

The step is the world entity's `Component.Frame.step_milliseconds`, set once at the start of each tick. Under
`app.run()` it is the time that really passed since the last tick, carried to the nanosecond so fractions of a
millisecond add up, and at most 100 ms, so a hitch doesn't teleport anything. A fixed step made everything move in
slow motion whenever a frame took longer than `frame_milliseconds` (Theseus A87: half speed at 25 to 40 ms frames). A
program that calls `app.tick()` itself, as tests and benchmarks do, gets `frame_milliseconds` every tick, so it stays
repeatable. The timer is stored inline and `RingTimers` is a one-row system (the step is read from the world's
`Frame` with a lookup), so counting down 10,000 timers costs about 0.32 ms a tick (`server_bench`, optimized; it
was 1.3 ms as a list system over the timers, the rung markers and the frame, which built a row object per timer). `timers_check`
tests it: a 50 ms repeating timer rings 6 times in 30 ticks of 10 ms and a 120 ms one-shot rings once, and 40 paced
ticks of 25 ms take 1,012 ms.

## Storage

Each component class has a column: a sparse set whose bookkeeping lives in raw `Memory`, found by its dotted class
name through `Columns`. The raw header holds the entity of each row, the tick each row was added, and a sparse
array from entity to row. `Column<T>` holds the values themselves. Removal swaps the last row into the gap.
`Column<T>`, `Slot<T>` and `Row<T>` are generic singletons, one per type, so a system's fill is typed code with no
lookup by name on the hot path.

Values are stored one of two ways:

- **Inline**: every component that fits a `Vector` (its fields are numbers, `Boolean`, enums or `String`) is kept
  in an `Items<T>` (D218), contiguous in memory. Nothing is declared; `Column.inline()` works it out at compile
  time, and `Row` and `Stream` test the same thing.
- **By reference**: any other component (one holding a list, another object, a nullable field) is a `List<T>`. A
  system's row holds the stored object, so writing a field changes the component.

`Lookup<T>().of(entity)` lends the stored item either way (D230), so writing a field of what it returns changes the
component. A borrowed result can't be replaced: `var layout = lookup.of(entity)` followed by `layout = made` is a
compile error, so pass the found and the new item to a small writer function instead.

A system with one row and no `Added` or `Removed` field runs on the fast path, `Stream<System, Row>`. It
walks the driver column and fills each row straight from the columns (D217): inline items are borrowed and written
in place, with no copy and no reference counting, and references are handed over as they are. The runner picks
it with `phase.argument_count() == 1` (D219), so systems with several rows still compile and use the combination
path. Other rows get a copy of inline items, which is written back after the system runs.

A system with two rows (and no link in the first) takes the smaller row as the outer loop and streams the larger one
inside it: `render_each(target: Target, modeled: Modeled)` fills the one window's row once and walks every model,
instead of pairing them through the general combination path. Scene Gather is written this way (`BeginView`,
`GatherModels`, `GatherCells`): 17,000 models went from 30 ms as a list system to 8 ms.

A `_all` system's rows are written back after it runs, like a single row's, so writing a field of an inline
component in a list sticks. Its row objects are kept between runs and refilled, and each entity is matched once
while the list is built, so a list system allocates its list and nothing per row.

## IO systems

A system whose phase function can reach a wait (a socket or file read, a sleep, a database call) is an **IO system**,
found at compile time (`$system_type.function_waits`, D209). Nothing marks it; writing straight-line code is enough:

```gdscript
func update_each(pending: Pending, store: Store) {
    var accounts = store.client.collection("accounts")
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
  A reference-stored component in the row is the stored object itself, so a write to it lands (after the frame).
  An inline component (any that fits a `Vector`, such as `Transform` or `Timer`) would be a copy, so **writing one is
  a compile error** naming the line (D261): the runner asks `function_writes_parameter` for every row that holds an
  inline component. A file or socket call added for debugging turns a system into an IO system, so it can surface
  this error too.
- A system with several rows queues each matching combination.

Because the compiler finds every function that can wait, it also catches file reads on the frame path, which the
no-stutter rule forbids: asset lookups go through `Recipes.Catalog`, which loads the cache index on the pool, and
shaders through `Recipes.Blobs`. `examples/io_systems` runs three MongoDB lookups with a 200 ms wait each while
frames keep ticking.
