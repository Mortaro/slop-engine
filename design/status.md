# Implementation status

What the [docs](../docs/README.md) leave out because it is status rather than documentation: what is not built yet,
known gaps, measurements over time, and the overview's status table. The docs describe the engine as it works and
say nothing about status; this page is where status lives. When something here is built, delete its line; when a
page gains something that is not built yet, add it here.

## The overview (README.md)

| | |
|---|---|
| Systems as phase functions over `type` rows, found by folder, no registration | built |
| Links between entities as components (`Parent`, `Owner`), followed by a two-row system, removed with their entity | built |
| Stages by read and write conflicts from `function.accesses`, a stage's systems on the thread pool | built (2026-10-02); reads and writes per whole row, see ecs.md below |
| Components pinned to their creating thread (`pinned_to_creating_thread()`) | built; the window path is compiled but not yet run on Windows |
| Window, mouse, button interaction, bitmap text | built, Windows only |
| Vulkan and software backends with pixel parity | built |
| Recipes as code, assets as declared classes, PSD, zstd, `.blend` structure | built |
| Read-only and filter-only access | built per whole row: markers are never fetched, and a row the system only reads is never written back nor conflicts with other readers; per field waits on per-piece accesses |
| Blender meshes, skeletons, skins, animations, textures | built ([docs/scene.md](../docs/scene.md)) |
| Thread pool (`Parallel`, `Concurrent`, IO systems) | built |
| Parallel iteration inside one system | not built |

The overview's examples were last verified on 2026-09-24: all of them ran, every `--debug-memory` run was balanced,
and the click test passed for 5 and 12 clicks.

## [ecs.md](../docs/ecs.md)

- The runner (D362, D363, 2026-10-02), known gaps:
  - `function.accesses` answers per whole argument, so a row that writes one component counts as writing every
    component in it (`parallel_check`'s `Drift` "writes" the `Velocity` it only reads). Scheduling by field needs
    per-piece accesses, which D335 left for `Changed<T>`. Re-checked on Spite master on 2026-10-02: not answered;
    the repro is in INSIGHTS ("what the runner's gaps need from the compiler").
  - A `Lookup<T>` attribute always counts as a write of `T`, because `accesses` does not count a write through
    what `of` lends (it comes from the `Column<T>` singleton; INSIGHTS bug 51), and a resource always counts as
    written, because `accesses` does not count a call that changes a singleton, nor an assignment to its fields
    (bug 52). Both still hold on master (2026-10-02); the cause is one rule in the compiler's write study, named in
    INSIGHTS. Holding the column's storage in `Lookup` itself would make `accesses` right, but D230 lends an inline
    item only from a singleton's storage, so that path is closed. When the compiler answers, the runner's
    `classify_attribute` notes the lookup's key and the resource's key with `written_names.contains(attribute.name)`
    instead of always as writes, and `parallel_check` gains the stage assertions: `Weigh` (reads `Armor` in a row)
    and `Witness` (reads `Armor` through a lookup) then share a stage.
  - Question for Mortaro: wait for the compiler, or give readers a way to say so now? Options: (a) wait (the fix is
    small and also serves `Changed<T>`); (b) a read-only lookup class, for example `Peek<T>`, whose `of` answers a
    copy, which the runner counts as a read; (c) a resource declaring itself read-only by a function, the way a
    component declares `pinned_to_creating_thread()`. Recommendation: (a); (b) and (c) add API that the compiler
    makes unnecessary, and (c) cannot be checked, so a wrong declaration would race silently.
  - A `Lookup<T>()` made inside a function body, or a column reached through another class (the flex layout's
    lookups), is invisible to the runner, as before: such a system can share a stage with a writer of that class.
  - Two systems of one stage that both create entities get ids in the order their threads ask, so ids (never the
    components, which commands apply in runner order) can differ between parallel runs.
  - A pinned system runs on the app's thread. A thread of its own per pinned class would need Spite's thread pool to
    take work for one chosen thread, which it does not offer.
  - Measured on Linux (4-core cloud machine, `--optimized`, interleaved runs of the binaries, medians, microseconds
    per tick):

    | Benchmark | Before the runner (`13e5890` with the operator rewrite) | Runner (`0a82f42`) | Runner plus settling after a large flush |
    |---|---|---|---|
    | `relations_check` | 10,677 | 7,992 | 7,499 |
    | `server_bench` | 10,967 | 11,423 | 10,972 |
    | `stress` | 18,613 | 19,314 | 17,655 |

    9 interleaved rounds of the three builds on 2026-10-02, load average about 0.6 to 1.1 (other streams idle).
    `relations_check` gains from rows that are only read no longer being written back. The `stress` and
    `server_bench` losses were not the runner: glibc keeps the small blocks a spawn frees (1.2 million for
    `stress`'s 200,000 bundles) in its fastbins and merges them all at once, about 20 ms for `stress`, at the first
    later malloc of 1 KB or more or free that leaves a 64 KB block. Before the runner that happened to fall after
    the timed ticks (in the profile's JSON); after it, in one tick (`Columns.release_buried` freeing its key list).
    With `GLIBC_TUNABLES=glibc.malloc.mxfast=0` the three builds tie. `World.flush` now settles the allocator after
    applying 4,096 changes or more (one 4 KB allocation, freed), so the merge lands in the spawn's flush, and a spawn
    no longer deep-copies inline components before copying them into the column. Whether Windows' heap defers its
    merging the same way is not measured yet.

- Which bundle class a value is cannot yet be asked reliably at run time (both forms are language bugs, D237), so a
  bundle the typed spawn path does not recognise takes the reflective path (`attribute.value` walked at run time),
  which is correct and slower: 200,000 bodies of four components in about 650 ms, against about 190 ms typed.
- There is no world pause or time scale yet (a server never pauses).
- Timers on the network: a running timer's data changes only when it starts, pauses, resumes or rings, so a
  mirrored timer would cost no traffic while it runs. Two things are missing for that (a game's alert A108): the
  game clock is each process's own, so a server's `ends_at` means nothing to a client, and the engine's components
  have no `mirrored_from`, so a game cannot mirror a `Timer` or a `Ticking`.
- `TickTimers` history: 0.27 ms for 10,000 timers through the clock row, against 1.25 ms through the pair path (which
  copies each row) and 0.34 ms for the one-row system before it (which looked the `Frame` up for every timer and
  wrote every timer every tick).
- Scene Gather went from 30 ms as a list system to 8 ms streamed (17,000 models).
- The last components that held an entity id as an `Integer` (`Viewer.entity`, `Observer.subject`/`observer`,
  `Sender.connection`, `Connect.connection`) became links on 2026-09-30.

## [plugins.md](../docs/plugins.md)

- `RenderVulkan.Renderer` shares one device between every window; each window made its own before.

## [ui.md](../docs/ui.md)

- `baseline` behaves as `flex_start` until text has baselines.
- Grid: not built yet: explicit placement (`grid-column`, `grid-row`, spans), `grid-template-areas`,
  `auto-fill`/`auto-fit`, `minmax()`, and the item alignment properties (`justify-items`, `justify-self`).
- Scrolling: not built yet: clicking the track to page, and a clip that an absolute element escapes when its
  containing block lies outside the scroller (today an absolute element is clipped by every clipping ancestor).
- Text input, known gap: Tab (handled by `Focus`) and characters typed in the same tick are handled by two systems,
  so a letter typed within the same frame as a Tab can land in the previous field. Not built yet: selection, the
  clipboard, caret blinking, and IME composition (which needs a real window procedure).
- Fonts: not built yet: kerning, outline and shadow, fake bold, hinting (Unreal renders Gulim with FreeType's
  default hinting), and embedded bitmap strikes.
- From Godot's coverage, not built yet: grid placement beyond auto-placement, text baselines, selection and the
  clipboard, and every control past the button, the combo box, the scroll container and the text field.

## [rendering.md](../docs/rendering.md)

- Windows now pump their messages once a tick on the app's thread (D363), replacing the dedicated window thread
  that kept pumping while a frame ran long. Not yet run on Windows: the README's `app.describe()` example, which was
  written before the runner changed.

- Spite cannot pass a function to C yet, so there is no window procedure written in Spite. Fullscreen and IME need a
  real callback; they wait on the language.

## [assets-and-recipes.md](../docs/assets-and-recipes.md)

- Hot reload, known gaps:
  - a recipe whose *code* changes through `--hot-reload` is not re-run yet: it waits on the language's
    `Reload().rebuilt_since(generation)` (D280), which `System.Recook` will poll;
  - fonts (`Recipes.Blobs`) and terrain materials don't follow the catalog yet;
  - the watcher is Windows-only and interim (a standard-library file watcher that Spite's own hot reload would
    share is Mortaro's decision).
- `examples/store_race_test` without the store lock: 5,965 of 8,000 records came back wrong or missing.

## [loaders.md](../docs/loaders.md)

- PSD: decoding straight into the texture's bytes, instead of `List<Integer>` one byte at a time, would cut the
  683 ms of a 10 MB splat map several times over (measured 2026-09-26). PSB is not read.
- `.blend`, not built yet: ear-clipping triangulation (faces are split as fans), custom split normals, more than one
  UV set, vertex colours, and cooking images that reference external files (the reader reports their paths).

## [scene.md](../docs/scene.md)

- Normal, roughness and metallic maps are not read yet.
- Dithered fades (Unreal's OccluderDither at a non-zero fade) are not built yet.
- A light that is a child of a moving entity reads only its own position (proposal: follow the parent once
  transforms have a world pass).
- Point and spot lights, not built yet:
  - shadows (a budgeted atlas, a proposal);
  - tighter sphere-against-cluster tests, which only cost shading a light that adds zero;
  - moving the cluster pass to a compute shader, if the CPU cost matters once many lights are on screen.
- Gathering 3,000 lights cost 0.9 to 1.1 ms at first, the ECS's per-row streaming cost rather than the lights; with
  cheaper singleton locks in Spite and inline storage it is 0.33 ms.
- `animate_bench` history (optimized, RTX 3090): Animate went from 81 ms to 9 ms, GatherModels from 11.4 to 6.6 ms
  and DrawScene from 22 to 5.7 ms, so the frame went from 122 to 26 ms. Animation once measured wall-clock time per
  row, which made a character's parts drift apart (the face slid off the head) whenever a tick's rows crossed a
  millisecond.
- `props_bench` history: a frame went from 60.6 ms to 13.9 ms with instancing and the ECS gather, with `DrawScene`
  from 26.8 ms to 2.2 ms.
- Not built yet, from the previous Kal renderer: the ray-marched atmosphere and sky; shadow cascades and contact
  shadows; GTAO; image-based sky lighting; bloom; 4× MSAA; automatic exposure from a histogram; Blender's custom
  split normals (`custom_normal` is ignored and normals are recomputed); blending between clips.

## [networking.md](../docs/networking.md)

The whole page is Claude's proposal, unconfirmed; Mortaro decides the API. It is built and tested by
`examples/click_counter_online` and `interest_check`. Not built yet, in rough order of need:

- **Values inline in columns** for the codec: copying a component's bytes instead of walking its fields.
- **Change detection by write, not by comparing.** Encoding every mirrored value every tick to compare bytes is
  fine for a counter and wrong for a world. It needs `Changed<T>`, which needs the compiler to say what a system
  writes (item 109 in the language's decisions).
- **A handshake** carrying the environment and a hash of every replicated component, so mismatched builds refuse
  each other instead of misreading, and a compile-time check that no two components hash to the same message id.
- **Unreliable delivery** (UDP) for state that is superseded every tick, prediction, and rates.

## [performance.md](../docs/performance.md)

GPU timestamps per pass are not built yet. There is no parallel iteration inside one system. Rows a system only
reads are no longer written back (2026-10-02, from `function.accesses`); skipping unread fields and scheduling by
field instead of by class need accesses per piece rather than per argument.

### `stress` over time

`spite stress --optimized`: 200,000 entities, `Move` and `Regenerate` in one parallel stage, 20 ticks.

| Version | Average tick |
|---|---|
| first version: a dictionary lookup per attribute per entity | 302 ms parallel, 422 ms sequential |
| column headers cached per system | 128 ms parallel, 133 ms sequential |
| generic singletons real, singletons not reference counted, `type` rows | 65 ms parallel, 81 ms sequential |
| per-runner command buffers, removal log per column | 48 ms |
| a single-row system streams its driver column (one match per entity, no per-tick candidate list, no re-match to store) | about 44 ms (runs that overlap other builds on the machine reach 115 ms) |
| thread pool and D183 singleton guards: one guarded `Row` call per entity | 108 ms until the guards stopped sharing cache lines (INSIGHTS bug 28); with the fix and D184, 46 ms parallel and 58 ms sequential |
| short strings inline (D203), production builds without debug machinery | 42 ms parallel; spawning 200,000 bodies 510 ms |
| stress components stored inline, single-row systems on the `Stream` fast path (2026-09-26, D221) | about 8 ms |
| Spite's reader-side singleton locks, lock skipped when no `Parallel` runs (2026-09-28) | 11.7 to 9.7 ms |
| runner on `function.accesses`, then a large flush settles the allocator (2026-10-02, Linux 4-core cloud machine, so not comparable with the rows above) | 19.3 to 17.7 ms |

### Where the time went (estimated, 2026-09-25)

About 150 ns per entity per system at 200,000 entities, where Bevy's simple iteration is around 1 ns. In order of
likely cost then:

1. **Components are heap objects.** Columns keep their values in `Column<T>` (a `List<T>` of references, or an
   `Items<T>` for components stored inline). The stress test ran at about 41 ms per tick on the old path, about
   8 ms inline on the `Stream` fast path.
2. **Reference counting on every visit.** Fetch, the row assignment and store add 4 to 6 retains and releases per
   component per system: about 3 to 5 million per tick.
3. **Per-tick bookkeeping** (fixed for single-row systems): systems with several rows still build candidate lists
   for their combinations.
4. **Per-frame scratch on the heap.** The layout's dictionaries and lists, and interpolated strings.

The benchmarks to race are ecs_bench_suite's: `add_remove` and `schedule` look winnable now; `simple_iter` and
`heavy_compute` need value columns; `frag_iter` favours Bevy's archetypes. zstd went from 1.15 s to 0.86 s on
261 MB when the bitwise functions (D117) replaced division by powers of two.

### Hitches, by status

| Source of a hitch | Status |
|---|---|
| Reading an asset, uploading a texture, whole-frame sync, upload bursts, mesh memory, freeing, the cache index, re-cooking | fixed (the table in docs/performance.md) |
| Mesh memory | fixed: vertex and index buffers used to live in host memory, which the GPU read over PCIe every frame |
| New font size | fixed: the glyph atlas used to start at 1024², whose million-texel fill took up to 22 ms in a game's UI |
| Thread start costs | open: a stage starts one OS thread per system per tick, and each load starts one. Needs D135's thread pool |
| Despawning many entities | improved: 200,000 entities (4 components each) in one tick, worst tick 480 ms, then 224 ms, now 22 ms (2026-09-26). About 28 ns per component removed; a single compacting pass per column would be cheaper when a large share of a column goes at once, and waits on `Items` gaining a move and a truncate. Removing from columns on several threads was tried and was slower (44 ms against 25 ms) |
| Texture decode format | open: textures are stored as a list of `Integer`s and converted to raw bytes on the worker. Should be GPU-ready bytes (and later block-compressed) in the store |
| Spawning a streamed region | open: needs spawning spread over frames. `create_entity_from_bundle` computes each component's column key as a string, so bulk spawning got 2x slower with the entity API (200,000 bodies: 520 ms to 950 ms), and short strings brought it back to 510 ms; integer ids per component class instead of string keys are the next step |
| Layout | open: the whole UI tree is laid out every frame. Fine for menus; an in-world UI needs dirty-subtree layout |
| Streaming a row | improved: a single-row `_each` system cost about 300 ns per entity even when its body only copied eight floats (`GatherPointLights`, 3,000 rows: 0.9 to 1.1 ms). Most of it was singleton locks: with Spite's reader-side locks, the lock skipped when no `Parallel` runs (d13aae7), and inline storage inferred, it is 0.33 ms, about 110 ns per row (optimized, 2026-09-28). The same change took `server_bench` from 7.7 to 7.4 ms. `stream_bench` (100,000 rows, optimized): one inline component 22 ns, two 37 ns, `Entity` plus one 31 ns, and an inline plus a reference component 180 ns, of which `Column.at` checking and then reading the item cost 35 (now one read, 143 ns). The rest is Spite's generated C: every reference fetched is retained and released (two atomic writes on a cold object, about 70 ns), every inline attribute retains its column's `Items` and takes the singleton guard (about 15 ns), and the row `Vector` is retained per row. Reported to Spite (2026-09-28) |

## [testing.md](../docs/testing.md)

- On Linux (2026-10-02, Spite master): the headless core and its examples build and run, balanced under
  `--debug-memory`; the store lock goes through `flock` there (`os/linux/`). Still Windows-only: the window, input
  and XInput plugins, the software presenter (GDI), Vulkan's `vulkan-1.dll`, and `Recipes.Watcher` (hot reload,
  `kernel32`); those examples were compiled for Windows in check mode only. The UI plugin loads `spite_truetype`,
  which must sit beside the engine, and the pinned MongoDB driver commit `ea1a143` does not compile with current
  Spite (`map_key` must be `map_keys`, `map_to_string` `map_to_strings`): it needs a driver commit and a new pin.
- On Windows (2026-10-02, Spite master `400b740`, with the operators migration merged in and `spite_truetype`
  pinned at `4963d04`, its D396 fix): every example in testing.md passes balanced under `--debug-memory`, including
  the pinned window path (the click, text field, drag and drop, combo box, scroll list and resize tests),
  `render_parity` (0 of 256,000 pixels differ), `hot_reload_test`, `live_asset_test`, `flex_layout` (92 of 92),
  `lights_check`, `terrain_check` and `attachment_check`. Only `io_systems` and `mongodb_check` fail, on the MongoDB
  driver pin above. Two examples building at once can collide checking out the same pinned package
  (`<package>.index.lock` exists); the second build fails and passes when run again.

- The tests that still capture at a frame number (`scene_probe`, `lights_check`, `terrain_check`,
  `kal_character`'s `--frames`) are to move to a trigger, as `render_parity` did. `render_parity` used to capture two
  rectangles short whenever a load finished one tick late.
