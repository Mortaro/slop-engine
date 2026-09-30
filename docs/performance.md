# Performance

## The numbers

`spite stress --optimized`: 200,000 entities, `Move` and `Regenerate` in one parallel stage, 20 ticks.

| Version | Average tick |
|---|---|
| first version: a dictionary lookup per attribute per entity | 302 ms parallel, 422 ms sequential |
| column headers cached per system | 128 ms parallel, 133 ms sequential |
| generic singletons real, singletons not reference counted, `type` rows | 65 ms parallel, 81 ms sequential |
| per-runner command buffers, removal log per column | 48 ms |
| a single-row system streams its driver column (one match per entity, no per-tick candidate list, no re-match to store) | about 44 ms (runs that overlap other builds on the machine reach 115 ms) |
| thread pool and D183 singleton guards (today): one guarded `Row` call per entity | 108 ms until the guards stopped sharing cache lines (INSIGHTS bug 28); with the fix and D184, 46 ms parallel and 58 ms sequential |
| short strings inline (D203), production builds without debug machinery | 42 ms parallel; spawning 200,000 bodies 510 ms |

About 150 ns per entity per system: better, and still about two orders of magnitude from a native ECS.

## Measuring: the profile

Every frame, the app times the whole frame, each stage and each system's `run_once` with the monotonic clock. The
cost is two clock reads per system per frame. `app.profile()` returns a `Profile.Report`: the frame, each stage and
each system as a `Profile.Entry` (name, phase, stage, runs, and average, last and worst microseconds).
`app.profile_json()` writes the report as JSON; `stress` prints it after its ticks:

```
{"frame":{"name":"frame",...,"average_microseconds":9317,...},
 "stages":[...,{"name":"stage 1","phase":"update","stage":1,"runs":20,"average_microseconds":9292,...}],
 "systems":[...,{"name":"System.Move","phase":"update","stage":1,"runs":20,"average_microseconds":9110,...}]}
```

Systems in one stage run in parallel, so a stage takes about as long as its slowest system, not the sum. An IO
system's time counts only the part on the frame (queueing its rows); the waits on its workers happen off the frame
and are not in the report. GPU timestamps per pass are not built yet. The profile API is a proposal by Claude.

## Where the time goes

- Every matched entity fills a row: each field is a typed read through `Slot<T>`, and a replaced component is written
  back.
- Every field counts, whether or not the system reads it; only markers are skipped. Skipping unread fields, never
  writing back read-only ones, and scheduling by field instead of by class all need the compiler to say what a
  function reads and writes (item 109 in the language's decisions file).
- Each system in a stage runs on the program's one thread pool (D191); there is no parallel iteration inside one
  system yet.
- `Row<T>` is a singleton with per-iteration state, so the compiler guards it (D183). The runner makes one guarded
  call per entity (`Row.advance()`: store the last entity, match and fill the next). Keep hot-path helpers such as
  `Raw`, `ColumnHeader` and `Slot<T>` free of state: a singleton that writes its attributes, or holds a plain class
  field, is guarded on every call.

## What already helps

- Column storage is raw memory, found once per system, not per entity.
- `Column<T>`, `Slot<T>` and `Row<T>` are generic singletons, so there is no lookup by name on the hot path.
- Markers have no values, fetches or write-backs.
- zstd went from 1.15 s to 0.86 s on 261 MB when the bitwise functions (D117) replaced division by powers of two.

## Where the time goes (estimated, 2026-09-25)

About 150 ns per entity per system at 200,000 entities, where Bevy's simple iteration is around 1 ns. In order of
likely cost:

1. **Components are heap objects.** Columns now keep their values in `Column<T>` (a `List<T>` of references, or
   an `Items<T>` for components stored inline, see [ecs.md](ecs.md#storage)). The stress test runs at about
   41 ms per tick on the old path. With the stress components stored inline and single-row systems on the
   `Stream` fast path, it runs at about 8 ms (2026-09-26, D221).
2. **Reference counting on every visit.** Fetch, the row assignment and store add 4 to 6 retains and releases per
   component per system: about 3 to 5 million per tick.
3. **Per-tick bookkeeping** (fixed for single-row systems): they stream the driver column and match each entity
   once. Systems with several rows still build candidate lists for their combinations.
4. **Per-frame scratch on the heap.** The layout's dictionaries and lists, and interpolated strings.

Mortaro (2026-09-25): "data oriented design for cache performance is very important, we need to make sure we are
using cpu cache as much as possible". The language's answers so far: D204, a `Vector<T>` whose items live inline and
whose `vector[index]` is a borrowed reference written in place (no copy, no reference count), which is the path to
component columns stored as values; and D203, strings of up to about 22 bytes stored inside the String value (no
allocation), for names and ids in components and on the network. SlopEngine waits for `Vector<T>` before moving its
columns. The benchmarks to race are ecs_bench_suite's: `add_remove` and
`schedule` look winnable now; `simple_iter` and `heavy_compute` need value columns; `frag_iter` favours Bevy's
archetypes.

## No stutters

Mortaro's rule (2026-09-25): "i wanna build huge open world shit with this engine, we cant have anything be blocking,
we cant have unreal engine like stutters". An open world streams all the time, so a frame may never wait for disk,
for the GPU beyond its own frame, for a compiler, or for a lock, and no single frame may take on an unbounded
amount of work.

| Source of a hitch | Status |
|---|---|
| Reading an asset | **fixed**: a `Parallel` job reads and decodes it; the frame only polls the thread (zero-timeout wait) |
| Uploading a texture | **fixed**: copied into the frame's persistent staging buffer and from there inside the frame's own command buffer; no extra fence wait and no allocation for staging |
| Shader and pipeline compilation (Unreal's PSO stutter) | **by design**: shaders are cooked by recipes, and every pipeline is created before the first frame. The rule is that no pipeline is ever created mid-game |
| Whole-frame CPU/GPU sync | **fixed**: 2 frames in flight (`RenderVulkan.Frame`: command buffer, fence, acquire semaphore, vertex buffer, target, staging). A frame waits only for the fence of the frame 2 before it, which blocks only if the GPU is two whole frames behind. Growing a buffer or resizing no longer idles the device |
| Upload bursts | **fixed**: textures and meshes share `upload_budget_bytes` (4 MiB) per frame. A texture larger than that streams in bands of rows across frames and is swapped in (mipmaps made on the GPU) once its last band lands, so the old image keeps showing until then; a mesh streams its vertex and index bytes in parts the same way. A draw whose texture or mesh isn't resident yet is skipped |
| Mesh memory | **fixed**: vertex and index buffers are device-local, filled through the staging buffer; they used to live in host memory, which the GPU read over PCIe every frame. A replaced mesh's old buffers are freed once the frames using them have finished |
| New font size | **fixed**: a size's glyph atlas starts at 256² and doubles when full, instead of starting at 1024², whose million-texel fill took up to 22 ms in Theseus |
| Thread start costs | open: a stage starts one OS thread per system per tick, and each load starts one. Needs D135's thread pool |
| Freeing big object graphs | **fixed**: a removed component's value moves (as raw bytes, no reference-count change) into its column's buried buffer, and each tick frees at most `app.release_budget` (4,096) of them |
| Despawning many entities | **improved**: removal records are per column in raw memory (a tick-ordered log and a per-entity "last removed" stamp, so `Removed<T>` checks are one read and trimming is O(trimmed)), despawns are applied a column at a time, and removal moves raw bytes. Each column removes the whole despawn list in one call, reading its header once and skipping empty columns. Despawning 200,000 entities (4 components each) in one tick: worst tick 480 ms, then 224 ms, now 22 ms (2026-09-26). That is about 28 ns per component removed; a single compacting pass per column would be cheaper when a large share of a column goes at once, and waits on `Items` gaining a move and a truncate. Removing from columns on several threads was tried and was slower (44 ms against 25 ms) |
| Cache index scan | **fixed**: `store.bin.index` mirrors every record (key, offset, length), so opening the store is one read. If the index is missing or disagrees with the store's size, the store is rescanned and the index rewritten |
| Re-cooking a changed source | **fixed**: recipes re-run on a worker, and the engine checks its loaded textures on another; the worst tick while a texture is re-cooked and reloaded is 2 ms |
| Texture decode format | open: textures are stored as a list of `Integer`s and converted to raw bytes on the worker. Should be GPU-ready bytes (and later block-compressed) in the store |
| Spawning a streamed region | open: needs spawning spread over frames. `spawn_entity_from_bundle` walks the bundle reflectively and computes each component's column key as a string, so bulk spawning got 2x slower with the entity API (200,000 bodies: 520 ms to 950 ms), and short strings brought it back to 510 ms; integer ids per component class instead of string keys are the next step |
| Layout | open: the whole UI tree is laid out every frame. Fine for menus; an in-world UI needs dirty-subtree layout |
| Streaming a row | **improved**: a single-row `_each` system cost about 300 ns per entity even when its body only copied eight floats (`GatherPointLights`, 3,000 rows of `PointLight` + `Transform`: 0.9 to 1.1 ms). Most of it was singleton locks: with Spite's reader-side locks and the lock skipped when no `Parallel` runs (d13aae7), and inline storage inferred, it is 0.33 ms, about 110 ns per row (optimized, 2026-09-28). The same change took `stress` from 11.7 to 9.7 ms a tick and `server_bench` from 7.7 to 7.4 ms. `examples/stream_bench` splits the rest by row shape (100,000 rows, optimized): one inline component 22 ns, two 37 ns, `Entity` plus one 31 ns, and an inline plus a reference component 180 ns, of which `Column.at` checking and then reading the item cost 35 (now one read, 143 ns). The rest is Spite's generated C: every reference fetched is retained and released (two atomic writes on a cold object, about 70 ns), every inline attribute retains its column's `Items` and takes the singleton guard (about 15 ns), and the row `Vector` is retained per row. Reported to Spite (2026-09-28) |
| Point and spot lights | **measured**: 3,000 lights, 79 on screen: clustering and upload 0.22 ms, gathering as above |

## Thread affinity

None. Windows belong to a dedicated window thread (`Windows.Owner`), which also keeps pumping messages when a frame
runs long; systems exchange requests and events with it through raw memory behind an SRW lock. Vulkan has no thread
affinity. So every system can run on any thread, and a stage runs its last system on the calling thread instead of
leaving it idle.
