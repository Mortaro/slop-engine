# Where the rules came from

The docs state each rule without saying who decided it or when. This page keeps that bookkeeping, page by page:
Mortaro's decisions with their dates and words, the Spite language decisions (D numbers, in the language's
`design/decisions.md`) a rule rests on, the alerts from games built on the engine that led to a change, and which
parts are Claude's proposals. Mortaro decides the API; a proposal stays marked here until he confirms it.

## README.md and [getting-started.md](../docs/getting-started.md)

- Every class in a `System` namespace is a system (D115); a system's function name says when it runs (D116); its
  parameter types are its query (D114).
- The `use_potion` example comes from Mortaro's notes.

## [ecs.md](../docs/ecs.md)

- No constructor taking an id: Spite has neither overloading nor visibility narrower than a class, so there is no
  constructor only the engine may call, and `world.entity_of(id)` replaced `Entity(id)`.
- No generics in the entity API (D123).
- `Lookup.of` and `has` crash on a negative id after reading outside the column once segfaulted a game.
- Information goes into components, implementation into systems (Mortaro, 2026-09-30).
- A component not in use is removed; a field never says "inactive"; no `Boolean` attributes (Mortaro, 2026-09-28).
- No `List` or `Dictionary` in a component (Mortaro, 2026-09-30).
- No `Parallel` in a component (Mortaro, 2026-09-30, resolving a game's alert A99).
- A component marks only what an entity has, never what it lacks (Mortaro, 2026-09-30).
- A link is a component holding only its entity, in a file of its own (Mortaro, 2026-09-30).
- Despawning walks the link columns rather than keeping a reverse index from entity to holders, which a system
  writing a link's entity in place would silently leave stale.
- No resources for state (Mortaro, 2026-09-25: "Resources shouldnt exist, its just a entity that is only used once
  instead, if we want to use it we query for that entity").
- A `_all` system does not run when its first list is empty (Mortaro, 2026-09-27: the fastest way to skip idle
  work).
- A row's `entity` field gets an `Entity` of its own: it once named whichever entity the runner filled next.
- Timers are components (Mortaro, 2026-09-30: "just make sure it's always ECS"); names follow Bevy's `Timer` (a
  proposal by Claude, accepted).
- The tick step is the time that really passed: a fixed step made everything move in slow motion whenever a frame
  took longer than `frame_milliseconds` (a game's alert A87: half speed at 25 to 40 ms frames).
- Inline storage in `Items<T>` (D218); `Lookup` lends the stored item (D230); walked rows (D217); the fast path
  chosen with `argument_count` (D219); IO systems found with `function_waits` (D209); writing an inline component
  of an IO system's row is a compile error (D261).
- The clock row is opted into by the row's class (a proposal by Claude).
- The runner uses no markers: what a system reads and writes comes from its phase function's `function.accesses`
  (D335), and systems that do not conflict run at the same time (Spite's D362, Mortaro, 2026-10-01, answering item
  109). Thread affinity is declared on the data, by a component class's `pinned_to_creating_thread()` (D363,
  Mortaro, 2026-10-01, naming D362's function), the same pattern as `mirrored_from`.
- Proposals by Claude while building D362 and D363 (2026-10-02), for Mortaro to confirm: pinned systems run on the
  app's thread, the one that calls `tick()`, and ticking from another thread crashes; a `Lookup` attribute and a
  resource count as written until `accesses` follows writes through them; markers, `Without` and `Removed` are
  reads; the stages stay consecutive runs in name order, so moving to read and write conflicts changes which systems
  share a stage but never the order in which their changes apply; `app.describe_accesses()`.

## [conventions.md](../docs/conventions.md)

- A component tied to an OS thread declares `pinned_to_creating_thread()` (D363), replacing the rule that no system
  has thread affinity and that OS-bound state gets a thread of its own.
- Program code never reads raw addresses (D178).

## [plugins.md](../docs/plugins.md)

- `Window.Component.Handle` is pinned (D363), so the Win32 systems that touch it run on the app's thread and the
  dedicated window thread (`Windows.Owner`, `Windows.Pump`) is gone, with `Requested`, `Opening`, `FinishOpening`
  and `StopWindows`. A window is opened when it has no `Handle` (`Without<Handle>`), and "the window is open" is
  `Added<Handle>`.
- Folders are snake_case (D181); a program's subfolders always load (D182); a `load` under an `if` on a `Build`
  field is folded at compile time (D186).
- Held keys are entities (a proposal by Claude).
- The spatial grid (a proposal by Claude).
- MongoDB queries as IO systems come with the compiler's "does this function wait" (D209).

## [ui.md](../docs/ui.md)

- Grid tracks as CSS text in one component (a proposal by Claude, since a component holds no list).
- Drag and drop (a proposal by Claude; Mortaro decides the API). A drag is never a click after a game's alert A79: a
  skill book row learned its skill when a drag ended inside it.
- The combo box (a proposal by Claude).

## [assets-and-recipes.md](../docs/assets-and-recipes.md)

- Recipes found by namespace (D115).
- The index is per executable because a game's test clients run from the same folder as its player client: with one
  shared index, the player's running client followed the others' re-cooks and its models switched materials
  mid-session.
- The store lock: before it, a writer took the end of the file as its record's offset and then wrote, and a second
  process appending in between made that offset point into the other's record, so a reader silently decoded another
  asset of the same kind.
- A format change re-cooks by itself (a proposal by Claude, asked for by a game), using the schema hash of D215.
- Worktrees must be nearly free (Mortaro's requirement). A package asks the program through a method it declares
  (D155); a worktree reopens only the classes it changes (D156). Mortaro's workflow: agents make cheap worktrees for
  him to test, and approved changes are merged into the real code.

## [loaders.md](../docs/loaders.md)

- `Zstd.BitReader` uses the bitwise functions of D117.

## [scene.md](../docs/scene.md)

- `mesh.add_section` (a proposal by Claude).
- Bone attachments (a proposal by Claude, for Mortaro to decide).
- The terrain shader is a port of the first game's Unreal `M_Terrain`, whose roughness and specular are 1 and 0.

## [networking.md](../docs/networking.md)

- Environments, replication and the wire are Claude's proposal, unconfirmed; Mortaro decides the API.
- There are no players in the engine, only observers (Mortaro, 2026-09-27).
- A message lives until a handler consumes it: before, every message was despawned after one tick, and a game
  (alert A75) lost a scripted client's first `/give` that way, silently.
- A message is an entity (a game's alert A109, Claude's proposal).
- The dial runs on the thread pool (D191).

## [performance.md](../docs/performance.md)

- The profile API is a proposal by Claude.
- Mortaro (2026-09-25): "data oriented design for cache performance is very important, we need to make sure we are
  using cpu cache as much as possible". The language's answers: D204, a `Vector<T>` whose items live inline and
  whose `vector[index]` is a borrowed reference written in place; and D203, short strings stored inside the String
  value.
- Mortaro's rule (2026-09-25): "i wanna build huge open world shit with this engine, we cant have anything be
  blocking, we cant have unreal engine like stutters".
- Each stage runs on the program's one thread pool (D191); `Row<T>` is guarded as a singleton with per-iteration
  state (D183).
- A flush that applies 4,096 changes or more settles the allocator's freed blocks before it returns, and a spawn
  copies inline components straight from the bundle (proposals by Claude, 2026-10-02): `stress` showed glibc merging
  the 1.2 million blocks a 200,000-entity spawn freed in whichever later tick first allocated or freed a large
  block, about 20 ms (INSIGHTS, "a tick that paid for the spawn").
