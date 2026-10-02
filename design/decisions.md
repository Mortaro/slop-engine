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
- `Changed<T>` (a proposal by Claude, 2026-10-02, building on D335 and D362): a per-entity stamp in each column,
  set when a writing system's row is written back, when `Lookup.of` lends the item, and when `add_component` adds or
  replaces it; a system never sees its own writes (its in-run writes fall before the tick it remembers, its flushed
  commands after); added counts as changed, as in Bevy.
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
- Textures cooked GPU-ready and block-compressed (a proposal by Claude, 2026-10-02, unconfirmed; game alert A3,
  design/status.md's "texture decode format"). Choices made, each the conventional one, for Mortaro to confirm:
  - `Asset.Texture` is `width`, `height`, `format` (text: `"rgba8"`, `"r8"`, `"bc1"`, `"bc3"`, `"bc4"`, `"bc5"`,
    `"bc7"`), `levels` and `texels` (every level, largest first), replacing `pixels: List<Integer>`; packed-pixel
    access is `pixel`, `set_pixel`, `append_pixel`, `pixel_count`, `clear_pixels`. A game's recipes that read
    `.pixels` move to these. `Asset.TextureArray` is layers of one shape, built with `append_layer`.
  - The settings copy Unreal's Compression Settings and their defaults (`TC_Default` as BC1 or BC3 by detected
    alpha, `TC_Normalmap` as BC5, `TC_Masks` linear, `TC_Grayscale` as uncompressed R8, `TC_BC7`,
    `TC_UserInterface2D` untouched), and the mip filter copies Unreal's default `SimpleAverage`.
  - The plugin is `slop_texture_compression_plugin` (`TextureCompression.Compressor`, `.Decoder`), named after
    Unreal's TextureCompressor module; a recipe loads it like any loader.
  - Colour textures upload as `UNORM` because the scene shader already decodes sRGB and the same slot can be drawn
    by the UI; switching to `_SRGB` formats (Unreal's choice, filtering in linear light) is the next step.
  - The terrain shader derives a layer normal's Z from X and Y, as Unreal does for every `TC_Normalmap` texture,
    so a BC5 array needs nothing else.

## [loaders.md](../docs/loaders.md)

- `Zstd.BitReader` uses the bitwise functions of D117.
- The `.blend` mesh reader ports Blender's own tessellation (`BLI_polyfill_calc`, the quad split) and corner normal
  code (`normals_calc_corners`, the encoded custom normal spaces) rather than writing its own, so a mesh looks the
  way it does in Blender; game alert A9 (a proposal by Claude, unconfirmed).
- Where Blender answers a zero normal for a fan whose space it cannot build, the reader keeps the fan normal (a
  proposal by Claude, unconfirmed): a zero normal draws black.

## [scene.md](../docs/scene.md)

- `mesh.add_section` (a proposal by Claude).
- Bone attachments (a proposal by Claude, for Mortaro to decide).
- Animation as a headless plugin (a proposal by Claude, 2026-10-02, for Mortaro to decide): the pose is
  `Animation.Component.Pose`, `Animate` no longer asks for a `Scene.Component.Model`, and
  `slop_scene_animation_plugin` shares the pose with the scene's `Skin` and maps `OffView` to
  `Animation.Component.Unseen`. The brief asked for animation that builds without the renderer, and a server needs
  poses for hit boxes and attachments. An unseen animator now keeps its time advancing (before, `Animate` skipped it
  whole, so it came back at the time it left).
- Blending, crossfades, loop start and throttling (proposals by Claude, 2026-10-02): extra clips are layer entities
  (children with `Animation.Component.Layer`) gathered into the `Animation.Layers` resource, blended as a normalised
  weighted average with the animator's own `weight`; a crossfade is a component with its own `elapsed` and the moment
  marker `Crossfaded`; `loop_start` is a field next to every clip name (see the question in status.md); throttling is
  `Animation.Component.Throttle` (`interval`, `phase`) set from `ThrottleBands` by distance to cameras and
  `Viewpoint` entities, sampling on `(frame + phase) % interval == 0` while time advances every tick.
- A looping clip lasts from its first key to its last (a bugfix by Claude, 2026-10-02): before, it lasted one frame
  more and interpolated from the last key back to the first, so a cycle whose last key repeats its first held that
  pose for two frames.
- The terrain shader is a port of the first game's Unreal `M_Terrain`, whose roughness and specular are 1 and 0.
- Grass and water come from a game's alert A57 (eleven landscape grass types and Gerstner oceans and lakes). Proposals
  by Claude (2026-10-02), unconfirmed, for Mortaro to decide:
  - the split follows lighting: `slop_foliage_plugin` and `slop_water_plugin` hold the components, gather them into
    the neutral `Scene.Grass` and `Scene.Water` resources, and `SceneVulkan.GrassPass` and `WaterPass` draw them, so
    a scene without those plugins has no grass and no water and pays nothing;
  - a grass type's `density` is per square metre, where Unreal counts per 10 m by 10 m; the cull fade shrinks
    instances as Unreal's instanced grass does; placement is a jittered world grid whose every choice is a hash of the
    cell, Unreal's `bUseGrid`;
  - what drives a type's density is a `DensityMap` component (a texture, a channel and the area it covers), since the
    game's grass is placed by mask textures rather than terrain layer weights; a type without one grows everywhere;
  - the ground the grass stands on comes from drawing the terrain cells in view from above each frame, so it works for
    any terrain mesh; grass casts no shadow;
  - `AlignToSurface` and `RandomYaw` are markers, as Unreal's `AlignToSurface` and `RandomRotation` are flags;
  - Gerstner waves are child entities of their body (a component holds no list), and a wave has no speed field: its
    angular frequency follows its wavelength by deep-water dispersion, which is how Unreal's `GerstnerWaterWaves`
    computes `WaveSpeed` and matches the game's exported values;
  - a body's absorption is given as distances in metres (Unreal's `Absorption` vector is the same distances in
    centimetres), and its colour comes from single scattering with an isotropic phase; reflections are of the sky only.

## [physics.md](../docs/physics.md)

Physics rests on Mortaro's decision of 2026-09-27 (recorded in the roadmap): completely ECS, so it runs beside
everything else, and the same 3D physics on the server and the client. Everything else on the page is a proposal by
Claude (2026-10-02), for Mortaro to confirm:

- Colliders are one shape component per entity (`BoxCollider`, `SphereCollider`, `CapsuleCollider`,
  `MeshCollider`) beside a `Transform`; a compound shape is several entities. Static by default, `Kinematic` for a
  collider code moves (read every tick), `Trigger` for a volume that blocks nothing; both markers are read when the
  shape is added. A primitive's size is its component's; the transform's scale applies only to meshes.
- A mesh collider's triangles are a `Physics.TriangleMesh` held by name in the `Physics.Meshes` resource (asset data
  held by an object, as `Scene.Pose` is), and the component holds only the name.
- **The query API is functions of a resource, `Physics.Colliders`**, not request entities answered by a system. A
  character controller makes several sweeps per character per tick and needs each answer before the next, a game's
  aiming or line-of-sight check wants its answer in the same function, and a request entity would cost a command, a
  flush and a tick of latency per query. The cost is the runner's: every system binding the resource counts as
  writing it, so querying systems share no stage with each other (they still share stages with everything else).
  Request entities can be added on top later for queries that come from the network. It is named `Colliders`, not
  `World`, because `World` is the core's and a `World` inside the `Physics` namespace would shadow it.
- `Physics.Hit` gives the collider as an `Entity` (a new one per hit, so keeping it is safe), the distance, the
  point and the normal, as plain floats like `Transform`.
- The broad phase is a spatial hash over the ground plane rebuilt by counting sort: static colliders only when one
  comes or goes, kinematic colliders and characters every tick; height is checked against bounds. Chosen over
  sweep-and-prune because a game's colliders spread over the ground and most queries are short.
- The narrow phase measures distances between cores (point, segment, box, triangle) and sweeps by stepping along a
  convex distance, which cannot pass a contact; boxes against boxes and triangles use separating axes.
- The character controller: `Character` (radius 0.4, height 1.8, step height 0.35, slope limit 45 degrees,
  gravity 9.81), `DesiredVelocity`, `VerticalSpeed` (a jump sets it), the `Grounded` marker added and removed only
  when it changes; the transform's position is the feet; a slope steeper than the limit is a wall; stepping accepts
  landing on an edge whose surface is walkable, no higher than the step height above the ground it left. It runs
  in `update`, so a game sets `DesiredVelocity` in `after_input`.
- Triggers: each overlap is an entity, a child of the trigger, holding the link `Visitor` and the markers
  `Entered` or `Left`, each living from one `TrackTriggers` to the next so every system sees it once (the same
  reasoning as `Rang`, which lives one tick). Triggers detect characters and kinematic colliders, not static ones,
  which never enter anything.

## [networking.md](../docs/networking.md)

- Environments, replication and the wire are Claude's proposal, unconfirmed; Mortaro decides the API.
- There are no players in the engine, only observers (Mortaro, 2026-09-27).
- A message lives until a handler consumes it: before, every message was despawned after one tick, and a game
  (alert A75) lost a scripted client's first `/give` that way, silently.
- A message is an entity (a game's alert A109, Claude's proposal).
- The dial runs on the thread pool (D191).
- Proposals by Claude (2026-10-02), for Mortaro to confirm:
  - replication sends what was written (`Changed<T>`) and still compares the new frame with the kept one, so a
    system that writes a row it leaves unchanged costs an encode but no bytes;
  - the hello carries the protocol, a hash of every replicated component's shape (class name, mode, each field's
    name and type, nested classes walked) combined so the load order does not matter, a datagram token and port,
    and the environment; a mismatch closes both sides and marks the dialer `Network.Component.Refused`, which stops
    `Dial`; nothing is sent to a peer before its hello matched, marked `Network.Component.Greeted`;
  - `CheckSchema` crashes on the first tick, naming `no_two_replicated_components_share_a_message_id`, rather than
    at compile time, since the ids are hashed at run time from the class keys;
  - unreliable delivery is opted into by a class function, `sent_unreliably(): Boolean`, beside `mirrored_from`
    (the same pattern as `pinned_to_creating_thread`); new entities, removals and messages stay on TCP; datagrams
    carry the sender's tick, a datagram older than the newest tick seen on either channel is dropped, and a value
    that stops changing is sent once more by TCP;
  - the server's clock: the dialer pings every 60 ticks and keeps `Network.Component.ServerClock` (offset, round
    trip, samples) on its world entity, and the marker `Network.Component.FollowServerClock` moves its game clock
    by the offset; an engine component is mirrored by reopening its class in the game's folder (Spite's reopening of
    classes from a later root), which answers a game's alert A108 without the engine knowing environments;
  - `Network.Component.DropDatagrams` for tests.

## [navigation.md](../docs/navigation.md)

- The roadmap's item 6 (a game's request, 2026-09-26: a walkability bitgrid cooked from terrain and collision at
  0.8 m, grid A*, line of sight).
- Plain classes and `List`s throughout, no `Raw` or `TypedMemory` (Spite's D398, D399, D402).
- Proposals by Claude (2026-10-02), for Mortaro to decide:
  - the bake as a recipe step (`Navigation.Bake`) whose output is an asset class (`Navigation.Asset.Walkability`:
    bits packed 32 to an `Integer`, plus a standing height per cell), and the span model borrowed from Recast
    (triangles clipped per cell, spans merged, highest floor with room for the agent, ledges dropped);
  - one grid per program in a `Navigation.Map` singleton;
  - A* with integer costs 1000 and 1414 and the octile heuristic, no corner cutting, ties to the deeper node; line of
    sight by the supercover line asking for both cells at a corner; string pulling;
  - regions labelled at load, so an unreachable goal is answered at once;
  - a path as waypoint entities (children of the bot, chained by the link `Next`, the bot's `Heading` naming the
    current one) rather than a list in a resource keyed by entity, since docs/ecs.md turns a list of items into
    entities; walking is a two-row system following `Heading`;
  - the names `Destination`, `Speed`, `Searching`, `Heading`, `Waypoint`, `Next`, `Arrived` and `Unreachable`;
    `Unreachable` says something the destination is, not something the bot lacks;
  - searches batched per tick, one `Parallel` per batch in the `Navigation.Searches` resource, each pool thread
    keeping its own `Navigation.Search` in a `ThreadLocal`; results land in `input` on a later tick;
  - `Destination` stays after `Arrived` and `Unreachable`, and a new destination is a remove and an add in the same
    tick, since a replaced component is not `Added`.

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
- GPU timings (a proposal by Claude, 2026-10-02, unconfirmed): `renderer.gpu_timings` with `begin(name)` answering
  a query index and `end(index)`, averages per name until `clear()`, read two frames later at the frame's fence.
  Named after the common engine practice of per-pass timestamp scopes; Mortaro decides the API.
