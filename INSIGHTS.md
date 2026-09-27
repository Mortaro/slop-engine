# What SlopEngine taught us about Spite

Written 2026-09-24 by Claude (Opus 5.5) while building the first version of SlopEngine. Everything marked
"proposal" is Claude's, unconfirmed: Mortaro decides.

## Update, later on 2026-09-24: the target API runs

Once the language shipped fixes 1, 2 and 15 and decisions D114–D117, `use_potion.spite`'s form runs almost as
written. See `examples/use_potion/system/consume_potion.spite`: `update_each(potion: Potion, target: Target)` over
`type` rows, the relation followed through `owner: Entity`, and `target.health = target.health + ...` written back.
Systems are found by folder, recipes too, and plugins are opted into by `load`. The click counter runs on it with
Vulkan, and parity and memory balance hold.

What is still open from the notes: filter-only and read-only access (compile-time reads and writes), environments
on declarations, and ordering inside a phase, which is by dotted name. Performance went from 133 ms to 81 ms
sequential and 65 ms parallel per stress tick.

New findings from adopting D114–D116 (the first three are fixed, fb3c814):

- **An empty `Symbol<Recipe>` or `Symbol<System>` range is a compile error, even in code never called.** Now an
  empty range walks zero times, so `Cook` is back in the core.
- **A row `type` is shadowed by the program's entry class of the same name** (`type Healing` in the program
  `healing`).
- **The matched `phase` Symbol can't be passed to a helper**, so a runner's loop lives inside the template.
- **Ordering inside a phase is by dotted name**, not data flow. Finer phase names (`after_input`, `after_render`)
  carry the ordering today. Compile-time reads and writes would let the engine order by data.

## The short answer (first version)

**Spite can build this engine today, but not with the API in `use_potion.spite`.** About a thousand lines of Spite
gave a working multithreaded ECS, a Win32 window with no C written, software rendering, a clicking button and a test
that drives it through real window messages. Every run has balanced memory. What's missing splits into three:

1. **Two compiler bugs block the target API directly**: plural templates over a `type`, and generic singletons.
   Both were reported to the language session and are being fixed first.
2. **Four capabilities the notes assume don't exist yet**: finding functions by name, calling a function with
   arguments built from its reflected parameter types, knowing at compile time which attributes a function reads
   and writes, and per-environment components. These are language design work, not bugs.
3. **Performance is about 100 times too slow**, and the causes are in the generated code, not in the engine.

## The target API, claim by claim

`use_potion.spite`:

```gdscript
type Target {
    health: Health
    alive: Alive
}

type Potion {
    item: HealingItem
    active: Active
    owner: Entity
}

func consume_potion_system(potion: Potion, target: Target) {
    target.health = target.health + potion.item.healing_amount
}
```

`examples/use_potion/consume_potion.spite`, what runs today:

```gdscript
var entity = Entity(0)
var item = HealingItem()
var active = Active()
var owner = Owner()
var world = World()

func run() {
    var healths = Lookup<Health>()
    var living = Lookup<Alive>()
    assert living.has(owner.entity)
    var target = healths.of(owner.entity)
    assert target
    target.amount = target.amount + item.healing_amount
    world.despawn(entity.id)
}
```

| The notes say | Today | What it needs |
|---|---|---|
| query rows are `type`s declared in the system's file | the system class's own attributes are the one query | **bug**: a plural template (`fill_attributes`) doesn't exist over a `type` shape, only over a class. Reported, HIGH |
| a system is found by its function name, no registering | a system is a class, found as an attribute of a plugin, and plugins are attributes of the composition. No list is written, but the plugin names each system | **feature**: a Symbol template ranging over the program's functions by name pattern. Proposal below |
| the system runs once with the matching rows as arguments | `run()` takes nothing and the engine fills attributes | **feature**: calling a function whose argument types come from reflection at compile time. `Spite.Function.call_function()` only calls functions that take nothing |
| `target` is the entity `potion.owner` points at | `Lookup<Health>().of(owner.entity)`, by hand | the two features above, plus a rule for how a second row is chosen. Proposal below |
| `alive` is never read, so it's a filter and locks nothing | `alive` is an attribute, so a component access like any other | **feature**: compile-time reads and writes per function. Proposal below |
| `healing_amount` is never written, so it's read-only and threads freely | every access counts as a write; stages are formed by class | same feature |
| `active` is server-only from its declaration; build once per environment | not built | **feature**: environment on a declaration. Proposal below |

### Decided: compile-time function reflection

Mortaro decided on 2026-09-24 that a system is a class with `run_each(potion: Potion, target: Target)` or
`run_all(potions: List<Potion>, targets: List<Target>)`, and that the gap is closed in the language with
compile-time function reflection: `if $system_type.has('run_each')` folds at compile time, and the function's
arguments become a compile-time list whose `.class` works as a type. Recorded as D114 in the language's docs/decisions.md.
The syntax is Claude's proposal, and it's in mortaros_missing_decisions.md with the `*_system` discovery question;
the mechanism is the decision. Rejected: variadic generics (fixes arity
only), and one engine class per arity (works sooner, reads worse).

A probe shows the base already works: a generic `Each(system.run_each)` infers `Each<Potion, Target>` from the
function value's type and calls it. It stops at bugs 2 and 15.

### Proposal: systems found by name

The engine already has everything but the discovery. A template over functions instead of attributes, over the
whole program rather than one class, would make the notes' form work with no registration:

```gdscript
func run_system(system: Symbol<Spite.Function>) {
    # instantiated once for each function in the program whose name ends in _system
}
```

The name hole already exists for attributes (`set_attribute` answers `set_age`). A suffix pattern over functions
is the same idea in the other direction. **Proposal**: `Symbol<Spite.Function>` in a function named
`<anything>_system` ranges over program functions whose names end in `_system`. `system.arguments` is then a
compile-time list whose `.class` works as a type, and `call_system(...)` passes values of those types.

### Proposal: the second row

`Potion.owner: Entity` and a second parameter `target: Target`: the rule "a row whose type has exactly one `Entity`
field chooses the entity of the next row" covers the notes' case. With no `Entity` field, two rows mean every
pair, which is almost never wanted, so it should be a compile error until someone asks for it.

### Proposal: reads and writes at compile time

The compiler already sees every statement of every function. Exposing `attribute.is_written_in(function)` and
`attribute.is_read_in(function)` as compile-time `Boolean`s inside a Symbol template, folded like `if $is_magic`,
would give:

- a filter-only component: not read and not written, so its column is checked but never fetched;
- a read-only one: fetched, never written back, and never a conflict with other readers;
- scheduling by field instead of by class.

It's the same analysis the compiler already does to call an unused local an error, only asked for by the program.

### Proposal: environments on declarations

D36 says hidden optimisations are welcome, and this is one. **Proposal**: a header line like `singleton`, e.g.
`environment 'server'` at the top of `active.spite`, and a `Build().environment` field. The compiler then drops
server-only components from a client build, drops every system that asks for one, and errors when a client-only
system reaches a server-only component. The engine needs no multi-environment code at all, which is exactly what
the notes ask for.

## Bugs found and reported

All sent to the "Language implementation review" session, which is fixing them one commit each, in this order:

| # | Priority | Bug | Workaround in SlopEngine |
|---|---|---|---|
| 1 | fixed | `singleton` plus `generic`: every call makes a new instance | columns found by class name in a `Dictionary`; `Slot`s allocated per access |
| 2 | fixed | plural Symbol templates don't exist over a `type` shape | query rows are class attributes, not `type`s |
| 9 | fixed | singletons are reference counted, atomically once a `Parallel` exists, so threads contend on `Memory()` | none: this is why parallel stages give 4% instead of 2x |
| 3 | fixed | the compiler hangs on `if found == Storage<$component_type> {`; a generic class name can't be used in a class test | raw `Memory` columns, no narrowing back from a shape |
| 4 | fixed | a shape's function can't be passed to `Parallel`: it's called instead of bound | `Job`, a class wrapping the shape |
| 5 | fixed | `$component_type.name` isn't allowed | `var sample: $component_type = null`, then `sample.class.name` |
| 10 | fixed | `.class` of a `DynamicLibrary` is taken for a foreign constant | libraries are locals in functions, never attributes |
| 11 | fixed | the unused-parameter check runs after a compile-time branch is folded | parameters used in both branches, as sanity crashes |
| 12 | fixed | `crash a and b` narrows neither path | one `crash` per path |
| 6 | fixed | `"{attribute.class}"` doesn't interpolate, though the docs say it prints as the type name | `attribute.class.name` |
| 7 | fixed | member templates (`map_name()`) don't exist on a list of a shape | a `while` |
| 13 | fixed | no clock in the standard library | `QueryPerformanceCounter` through `DynamicLibrary` |
| 14 | fixed | no error when a program's entry folder name matches another class in it | renamed the folder `use_potion` |
| 16 | fixed | programs run with the working directory set to the compiler's repository (bin/spite does `cd "$here"`), so every relative path a program opens is wrong | paths joined to `Build().program`, the absolute entry folder |
| 17 | fixed | a method named `allocate` collides with the generated `<Class>_allocate` and fails in clang, not in Spite | renamed `allocate_memory` |
| 18 | fixed | a namespaced type in a type position (`swapchain: Component.Swapchain`, `Remove<Component.Created>`) doesn't resolve relative to the folder, though the same constructor does | full names (`RenderVulkan.Component.Swapchain`) |
| 19 | fixed | a `DynamicLibrary` call passes a literal `0` as a 32-bit int even where C takes 64 bits, silently | a typed local per 64-bit argument (`var no_offset: Long = 0`) |
| 20 | design | a program that loads another program's folder merges root classes of the same name (`composition.spite`, `plugin.spite`) | the parity test names its own `ParityComposition` |
| 21 | fixed | singletons destroyed in creation order at exit: a drop() calling a DynamicLibrary finds it unloaded (segfault) | the renderer is released by a system reacting to `Resource.Quit`, in a last tick |
| 22 | fixed | lazy singleton creation has no lock, so two Parallel threads can create one twice | none yet; being fixed |
| 23 | fixed (D117) | no bitwise operators: every binary format (zstd, FSE, Huffman, PSD flags, Win32 parameters) is written as division and remainder by powers of two | `Zstd.Powers` |
| 24 | HIGH | arithmetic takes the left operand's type: `Integer * Long` is an Integer multiply and silently overflows | a typed local (`var next: Long = ...`) |
| 25 | fixed | a generic class in a namespace can't be constructed ("not supported in this stage"), and the error cascades | generic classes at the package root (`Pack`, `Field`) |
| 26 | fixed | the compiler segfaults on a folder class referenced from its own namespace | the test plugin is `ClickTest.TestPlugin` |
| 27 | fixed | inside a namespace there's no way to name a root class shadowed by a local one (`Plugin`) | distinct names |
| 28 | fixed | D183's singleton guards are 16-byte statics side by side, so two systems' `Row<T>` guards share a cache line: stress went from 45 ms to 108 ms per tick with zero lock contention (padding each guard to 64 bytes restores 45 ms). Also: calls a singleton makes to itself go through the wrapper, singleton access counts references atomically (about 20 of the 45 ms), and a singleton holding any non-singleton class field is guarded even if nothing writes it | stateless helpers (`Raw`, `ColumnHeader`) stay singletons, `Slot<T>` keeps no state, one guarded `Row` call per entity (`Row.advance()`) |
| 29 | fixed | `return $T.has_function("x") or ...` as a value in a generic emits unused debug printers for every type, one naming a function that doesn't exist (`Columns_AnyColumn___call_to_debug`): the program fails to link | `if $T.has_function(...) { return true }` |
| 30 | fixed | `component.class.has_function("x")` inside a `Symbol<Component>` walk is not decided at compile time, so every branch is compiled for every component class | the check moved into a generic class (`Network.Codec<T>`), where `$T.has_function` folds |
| 31 | fixed | a class with no attributes has no `read_attributes` / `write_attributes` template, so `Pack<Marker>` fails to compile | the codec only builds `Pack<T>` behind the compile-time replication check |
| 32 | partly fixed (console flushes per line; kebab run-time flags are item 153) | run-time `Environment` flags take the field's spelling (`--lifetime_seconds`) while compiler flags must be kebab-case (`--repl-port`); and console output of a process whose stdout is a pipe or file is only flushed at exit | the snake_case spelling; logs read after the server exits |
| 33 | fixed | a method of a locked singleton passed as a function value (`found.filter(matches)` inside `Row`) generates a call to `spite_function_value_..._matches___unguarded`, which is never declared: C fails to compile | a `while` that calls a helper taking the list and the element |
| 34 | fixed | a `Concurrent` whose call chain passes template-made arguments (`system.phase_each(made_arguments())`) runs as a plain call, so every wait in it blocks | none: IO systems work but still block until it is fixed |
| 35 | fixed | a program that contains a `Concurrent` and uses `Parallel` leaks under `--debug-memory` by a varying amount (35 to 53 in `click_counter_test`) and allocates about a thousand more | none yet |
| - | done (D216) | reading a finished `Parallel`'s value counts as a wait, so `function_waits` calls texture-loading systems IO systems; asked for `finished_value(): T?` that is never a wait | none |
| 15 | fixed | a default `type` value isn't an object: every field read returns a fresh default (`return Health_default();`), so `target.health.amount = ...` is silently lost | none: blocks the decided system design (README) |
| 36 | fixed | a singleton function call per row costs a lock: reading reference-stored components through `Column<T>.at()` took 350 ns a row against a direct `values[...]` read, and 44 ms against 25 ms when removals ran on threads | components stored inline; lock-free reads of singletons not written during a stage are being built |
| 37 | reported | a `type` row naming a class that doesn't exist (`Server.Component.Eye` for a component in an environment folder) crashes the compiler (`Generator.shape_default`) instead of reporting the field | the right name, `Component.Eye` |
| 38 | reported | a template instance can silently share a name with an ordinary function (`store_attribute` for an attribute `row` makes `store_row`), and the error points at line 0 with a wrong argument count | rename the helper |
| 39 | D230 | a function can't return a borrowed `Items` item, so `Lookup.of` on an inline component returns a copy and writes to it are silently lost | components opt into inline storage (`stored_inline`) until D230 lands |
| 40 | fixed (D227, D228) | a program can't override a package's `Build` default, and a package can't find its own files, so shader recipes only worked two folders below the repository | junctions in Theseus |
| 41 | reported | comparing a value with a walked symbol's class (`given == bundle.class`) leaks the class object and its two lists, once per class | none: the leak is bounded; `debug-memory` counts are off by three per bundle class spawned |
| 42 | reported | `var bundle: T = null` constructs a default `T`, and everything it holds, which is then thrown away; `= null` reads as "nothing yet" | `T?` |
| 43 | reported | singletons that bind each other in a circle (`World` → `Column<Entity>` → `Columns` → …) hang at startup with no output instead of failing to compile; hit twice | a non-singleton helper holds the binding (`ChildFinder`) |
| 8 | design | a `_name` attribute is private even to a `Symbol<Class>` template reading it | filters are named normally; sent to Mortaro's decisions file |
| - | design | a class reopened from the program root gets new attributes, but its constructor loses to the loaded folder's version | the test sets window settings in its entry function; sent to Mortaro's decisions file |

## Gaps that aren't bugs

- **No callbacks from C.** A Win32 window normally needs a window procedure. SlopEngine registers `DefWindowProcA`
  as the procedure and reads mouse messages from the queue before dispatching them. That works for a button, but
  keyboard text, resizing and anything sent rather than posted needs a real callback.
- **No thread pool and no parallel iteration.** Each stage starts one thread per system, every tick. Splitting one
  system's entities across cores (`parallel_each_`) is listed as not built in concurrency.md; an ECS wants it more
  than anything else in that list.
- **Nothing says what a `Parallel` function may touch.** SlopEngine's stage rules are the only safety. A system
  that spawns without asking for `World` races, and nothing catches it. Compile-time reads and writes (above) would
  let the compiler check this instead of the engine trusting it.
- **No bitwise operators or hex literals.** Win32 packs positions into `lParam` (`position % 65536`,
  `position / 65536 % 65536`), styles are sums of decimal flags (`13565952 - 65536 - 262144`), and a colour is
  `red * 65536 + green * 256 + blue`. It reads badly, and a flag already set gets added twice without anyone
  noticing.
- **No 16-bit `Memory` writes.** `BITMAPINFOHEADER` wants two shorts, so planes and bit count go in one `write_integer`
  as `32 * 65536 + 1`.
- **No address of a `String`.** `WNDCLASSA` needs a `char*` inside a struct. The name is copied into allocated
  bytes with `kernel32.lstrcpyA`.
- **Every attribute is a query, and the engine can only check that at run time.** A constant attribute
  (`var frames_per_click = 4`) used to make a system wait for an `Integer` component forever, and it cost a debugging
  round. The `component/`, `system/` convention now makes the engine crash at startup on any attribute
  that isn't a `Component.*`, a singleton or `Entity`. It should be a compile error, but a template has no way to
  raise one: `attribute.class.namespace` and `is_singleton()` are run-time values, not foldable like `$is_magic`.
  **Proposal**: compile-time reflection of a class's namespace and `singleton` line inside Symbol templates, plus a
  template-level `crash` the compiler evaluates (a static assert). Every rule an engine wants to impose on its users
  would then be a compile error with the engine's own message.

- **No thread-local state and no locks.** Structural changes queue on one `World`, so a system that inserts must
  run alone in its stage. Bevy's answer (a command buffer per system, applied at sync points) doesn't need
  thread-locals in Spite: each `Runner<T>` owns its system instance, so the runner can put a per-runner `World`
  handle into the system's `world` attribute. That is the plan (Mortaro: "we want to beat bevy performance however
  we can"), to be built with the entity API. Spite doesn't need to add anything for it.
- **`Clock` has only milliseconds.** A frame budget is measured in microseconds; the stress example keeps its own
  `QueryPerformanceCounter` wrapper (`Stopwatch`).

## Update, 2026-09-25: no resources, and what D118 cost

Mortaro removed resources: state is a component on an entity (the world entity or a window), `World` is the only
singleton, and main-thread affinity is declared on the component class (`requires_main_thread()`, found with
`has_function`). Spite needed nothing new for this. Components are stored by reference (`TypedMemory`), so even the
Vulkan renderer, with its lists and handles, is a component at no copying cost.

D118 (an attribute nothing reads is an error) first landed counting reads per program. Every program that used
part of a library then failed: a window bundle nobody spawned, UI colours nobody rendered. The language session
changed it: a loaded package's public attributes are exempt (D136), and the Spawn template's value read counts. What
remains strict, and useful: the scheduling markers (`var main_thread = Resource.MainThread()`, read only as
`attribute.class`) were errors, and that is what pushed the markers out in favour of affinity declared on the data.

- **`File` reads and writes only whole text files.** A content-addressed cache binary needs binary, seekable
  reads (`read_bytes(offset, count)`) and appends. SlopEngine goes through the C runtime (`fopen`/`_fseeki64`/
  `fread`), on a `Parallel` thread so the frame never waits. `Parallel` has no way to ask "finished?" without
  joining, so the engine polls the thread handle with `WaitForSingleObject(handle, 0)`: a `finished()` that never
  blocks belongs in the library.
- **The entry folder loses to what it loads** (section 11: later loads win). Mortaro kept that (D155): a package
  asks the program for settings through a method the program declares, with a `has_function` default. That needs a
  generic helper (`Recipes.Setting<Build>`), because `has_function` only folds on a `$` type.

- **A folded constant overflows silently.** `var wheel: Long = (65536 - 120) * 65536` is computed in `Integer` and
  wraps; only clang's warning on the generated C noticed (reported 2026-09-25).
- **Name patterns catch helpers.** Phase functions are found by the `_each`/`_all` suffix (D116), so a helper named
  `drag_all` becomes a phase, and the error surfaces inside the runner's template. A pattern constrained to a list
  of names, or an error at the declaration, was asked for.
- **`discard` under Vulkan 1.3 needs a device feature.** glslang emits demote-to-helper-invocation; the clip test
  writes a transparent pixel instead, which straight-alpha blending leaves unchanged.

- **No `String` from a character code.** Turning a `WM_CHAR` code into text goes through `Memory`: allocate a
  byte, write it, `memory.text(address, 1)`.

## Update, 2026-09-25: the entity API runs

`world.create_entity()`, `world.create_entity_from_bundle(bundle)`, `entity.add_component(component)`,
`entity.remove_component(ComponentClass)` and `entity.remove()` replaced `Spawn`/`Insert`/`Remove<T>` across the
engine and every example, with memory balanced and every test passing. What made it possible was D123's two
features: the class test against a `$` type narrows `Anything` back to a column's own type, and `attribute.object`
walks a bundle at run time. A class passed as a value (D124) keeps `remove_component(Ui.Component.Hovered)` free of
generics.

- **Thread-local storage is missing.** Per-runner command buffers need each thread to know its runner. SlopEngine
  uses Win32 `TlsAlloc`/`TlsSetValue`/`TlsGetValue` and an SRW lock for ids; a portable `ThreadLocal<T>` (or a
  runner-scoped value the language passes down) belongs in the library.
- **Reflection per call is slow in bulk.** `bundle.attributes` builds a list of attribute objects on every call,
  and a column key is a string built from the class's namespace. Spawning 200,000 bundles went from 520 ms to
  950 ms. A compile-time walk of a known bundle class (still available when the caller knows the type) or cached
  per-class keys would recover it.

- **File watching belongs in the library.** Spite's hot reload has private per-OS watching; SlopEngine's cooker
  needs the same, so a public `FileWatcher` reporting changed paths was proposed (Mortaro to decide the name). Also
  missing: a file's last-write time and size (`file.modified()`/`file.size()` are on the way).
- **A `DynamicLibrary` can't be passed as a parameter**: a foreign call must go through the attribute or local that
  holds it, so each function binds its own.
- **A thread's function bound to its owner is a reference cycle.** `Parallel(watcher.run)` held by the watcher
  keeps both alive forever; the fix is a separate loop object holding only raw addresses, which D179 now requires
  anyway.

- **A singleton's automatic lock covers whole calls (D183).** A never-ending loop written as a singleton method
  (`Windows.Owner.run()`) holds it forever and every other thread's call waits: the click test hung. Long-running
  loops and long tasks now live in plain objects holding raw addresses (`Windows.Pump`, `Recipes.CookTask`), and the
  frame thread never calls a singleton a worker is inside (`System.Recook` owns the cook's handle). Mortaro has
  the design question (item 156).
- **A SlopEngine bug found by the language session's AddressSanitizer build**: `Added<T>` (and three other readers)
  read a marker component's value slot, which a marker column never writes, so it retained heap garbage from
  `Memory.resize` and crashed intermittently. Readers now skip markers. My first diagnosis (that `Parallel` doesn't
  keep its receiver alive) was wrong. A `--debug-memory` build that poisons fresh memory would make such reads fail
  every time; that's with Mortaro.
- **Two same-named types printed identically in a mismatch** ("a List<Buildable> cannot be used where a
  List<Buildable> is needed"); the message now names their owners. (A segfault I first blamed on naming a nested
  type was the program crashing in run mode from the marker bug above, not the compiler.)

## Vulkan through `DynamicLibrary`

SlopEngine's Vulkan backend is about 1,000 lines of Spite. It runs a Vulkan 1.3 instance with the validation
layer, device choice, dynamic rendering, a pipeline with per-instance vertex data, an offscreen target, readback, and
a mailbox swapchain with a semaphore per image. It draws the click counter with **0 of 256,000 pixels different**
from the software rasteriser, and the validation layer stays silent. `vulkan-1.dll` exports every call it needs, so
no loader or bindings were written.

What made it harder than it should be:

- **No C struct layout.** A `type` of numbers crosses as a struct, but a Vulkan struct holds pointers to other
  structs, strings and arrays. `RenderVulkan.Structure` writes fields in order and pads to natural alignment, which
  works, but a wrong field is a silent wrong struct. `Type.size` and header-checked layouts (listed in the manual as
  not built) would catch it at compile time.
- **Argument widths come from Spite values** (bug 19). A header-typed `DynamicLibrary` would make every call
  checked.
- **No `write_float` or `write_short` on `Memory`.** Floats go through `TypedMemory<Float>`.
- **No callbacks** still means no debug messenger. The validation layer prints to stdout by default, which was
  enough.

## Performance

`examples/stress`: 200,000 entities, `Move` and `Regenerate` in one stage.

| | average tick |
|---|---|
| first version, a dictionary lookup per attribute per entity | 302 ms parallel, 422 ms sequential |
| column headers and rows cached per system | 128 ms parallel, 133 ms sequential |

The generated C shows where the remaining time goes. For every attribute of every matched entity, twice (fill and
store):

- `Slot<Position>()` mallocs a `Slot` and, in its initializer, a `TypedMemory<Position>` (bug 1);
- every singleton (`Memory()`, `Columns()`) is retained and released, atomically, on a counter every thread shares
  (bug 9);
- `list[index]` answers a `T?`, so every cached-header read is a bounds check plus a narrowing branch.

With bugs 1 and 9 fixed, a fill should be two memory reads and a pointer copy. I'll re-measure when they land. The
next step after that is column storage by value instead of by pointer, which needs `TypedMemory` of a class laid out
inline: the same question as `Type.size`, which is already listed as not built.

## What worked better than expected

- **Systems as classes fit Spite.** A file is a class and the attributes are at the top of it, so a system's
  query is the first thing a reader sees. D-119 ("a system does its whole job in its own file") needed no rule.
- **Resources are singletons.** No `Res<T>`, no resource registry: `var mouse = Input.Mouse()` in a system is the
  resource, and the engine recognises it with `is_singleton()`.
- **Plugins and compositions are attribute lists.** A plugin is one plain class, by construction: `App` walks the composition's attributes, then each plugin's, with plural
  templates. There is no registration API because there doesn't need to be one.
- **Tests are mods.** `click_counter_test` loads the shipped game and reopens its `Composition` with one line,
  `var click_test = ClickTest.Plugin()`. The test runs the real composition plus its own plugin, and the game ships
  without test code.
- **`DynamicLibrary` was enough for a window and a framebuffer**, with no header, no binding file and no C.
- **The compiler's refusals were right almost every time.** Of the errors I hit, about half were rules that
  for_ai_writers.md does state (single letters, nested calls, `assert` in a constructor, `info`, copying to narrow).
  Each error message said exactly what to write instead, so none cost more than one round.

## Docs

Mortaro asked me to tell the docs author when the docs caused mistakes. Most of my mistakes were rules the docs
state clearly. The ones the docs caused were sent to the language session:

- `none` behaves as a reserved word (`var none: Long = 0` fails with "the empty value is written 'null'"), and no
  page says so;
- metaprogramming.md says `attribute.class` prints like the type name, but interpolating it is an error (bug 6);
- failure.md doesn't say that `crash a and b` narrows neither path (bug 12);
- packages.md doesn't say which side wins when a program root and a loaded folder both define the same function.

## Update, 2026-09-27: what the Theseus port taught

Mortaro set the goals: Spite first, as the best language for AI (fastest, fewest ways to get things wrong), then
Theseus beating its Unreal version while being simpler to maintain. The traps found while building for Theseus, and
what each became:

- **Silent copies are the worst class of bug.** An inline component read through a function returns a copy, and a
  write to it vanishes with no error (bug 39). The fixes moved the rule into the compiler: walked rows (D217) and
  lent borrows (D220, D230), so the only way to write is the way that sticks. The engine now also writes `_all`
  rows back itself. An opt-in such as `stored_inline` is a trap of the same kind, a thing the game must remember;
  it goes away with D230.
- **Performance traps look like correct code.** A singleton call per row (bug 36), a `List` of row indices instead
  of a `Vector` (30 ms to 11 ms), per-row name lookups (40 ms to 173 ms), and relation rows paired as a full
  cartesian product: each was fixed in the engine or reported, but an AI writing a game would not have seen them.
  The profile (`app.profile_json()`) and `server_bench` exist so these show up as numbers.
- **Folded questions beat opt-ins.** `argument_count` (D219), `function_runs_in_pieces` (D229, coming) and
  `fits_vector` let the engine choose the fast path itself; Mortaro's rule is that game code never changes for
  speed.
- **Wall-clock time inside systems is a bug magnet.** Animation sampled the clock per row, so a character's parts
  drifted apart. Systems now read the fixed tick step.

## Suggested order

1. Bugs 1, 2 and 9 (in progress). They unblock `type` rows and the performance path.
2. Compile-time reads and writes of attributes. This is the notes' filter and read-only claims, and it's also what
   makes `Parallel` safe.
3. Systems found by name, called with arguments from reflected types. This completes `use_potion.spite`'s form.
4. Callbacks from C. Needed for a real window: keyboard, resizing, IME.
5. Environments on declarations. Needed before Theseus's server exists.
