# Performance

## Measure a production build

Measure only a production build: `--optimized`, with no `--repl`, `--repl-port`, `--hot-reload` or `--debug-memory`.
REPL and hot-reload builds are slower on purpose: they exist to show more while the program runs (functions in
swappable slots, breakpoints, live inspection), not to be fast, so a number measured on one describes the tooling,
not the engine.

`spite stress --optimized` runs 200,000 entities through `Move` and `Regenerate` in one parallel stage and prints
the tick time; `server_bench`, `stream_bench`, `props_bench` and `animate_bench` measure the server, row streaming,
static props and skinned characters (see [testing.md](testing.md)).

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
and are not in the report.

## Measuring the GPU

`RenderVulkan.Renderer` times its passes on the GPU with timestamp queries, one pool per frame in flight. A pass is
timed by a begin and an end around its commands:

```gdscript
var timing = renderer.gpu_timings.begin("shadows")
record_shadows(renderer, drawn, storage)
renderer.gpu_timings.end(timing)
```

A frame's results are read when its fence is waited on, two frames later, so timing never stalls the GPU. Each
name's average accumulates until `renderer.gpu_timings.clear()`; `average_milliseconds(name)` reads one and
`describe()` lists every pass in microseconds. The engine times `frame` (the whole command buffer), `grass scatter`,
`shadows`, `scene` (with `grass` timed inside it), `water`, `tone map` and `ui`. `examples/render_bench` prints them
for a fixed scene with no grass and no water (optimized, 1920x1080, RTX 3090):

```
frame 544 us
grass scatter 0 us
shadows 76 us
scene 433 us
grass 0 us
water 0 us
tone map 16 us
ui 0 us
```

## Where the time goes

- Every matched entity fills a row: each field is a typed read through `Slot<T>`, and a replaced component is written
  back if the system writes that row.
- Every field counts, whether or not the system reads it; only markers are skipped. Ask only for the components a
  system uses.
- Each system in a stage runs on the program's one thread pool; one system's rows are walked on one thread.
- `Row<T>` is a singleton with per-iteration state, so the compiler guards it, and the runner makes one guarded call
  per entity. Keep hot-path helpers such as `Raw`, `ColumnHeader` and `Slot<T>` free of state: a singleton that
  writes its attributes, or holds a plain class field, is guarded on every call.
- A single-row system streams its driver column: inline items are borrowed in place, with no copy and no reference
  count ([ecs.md](ecs.md#storage)). A row of inline components costs a few tens of nanoseconds; a reference-stored
  component in the row costs several times more, since each one fetched is retained and released.

## What already helps

- Column storage is raw memory, found once per system, not per entity.
- `Column<T>`, `Slot<T>` and `Row<T>` are generic singletons, so there is no lookup by name on the hot path.
- Components that fit a `Vector` are stored inline, contiguous in memory, with nothing declared.
- Markers have no values, fetches or write-backs.

## No stutters

An open world streams all the time, so a frame never waits for disk, for the GPU beyond its own frame, for a
compiler, or for a lock, and no single frame takes on an unbounded amount of work.

| Source of a hitch | How the engine avoids it |
|---|---|
| Reading an asset | a `Parallel` job reads and decodes it; the frame only polls the thread (zero-timeout wait) |
| Uploading a texture | copied into the frame's persistent staging buffer and from there inside the frame's own command buffer; no extra fence wait and no allocation for staging |
| Shader and pipeline compilation | shaders are cooked by recipes, and every pipeline is created before the first frame. No pipeline is ever created mid-game |
| Whole-frame CPU and GPU sync | 2 frames in flight (`RenderVulkan.Frame`: command buffer, fence, acquire semaphore, vertex buffer, target, staging). A frame waits only for the fence of the frame 2 before it, which blocks only if the GPU is two whole frames behind. Growing a buffer or resizing never idles the device |
| Upload bursts | textures and meshes share `upload_budget_bytes` (4 MiB) per frame. A texture larger than that streams in bands of rows (of 4x4 blocks for a compressed one, level after level) across frames and is swapped in once its last band lands, so the old image keeps showing until then; a mesh streams its vertex and index bytes in parts the same way. A draw whose texture or mesh isn't resident yet is skipped |
| Texture memory and upload size | recipes cook textures block-compressed with their mips (BC1 is 1/8 of RGBA8 with GPU mips, BC3, BC5 and BC7 1/4), so a load copies one block and an upload moves the GPU's own bytes |
| Mesh memory | vertex and index buffers are device-local, filled through the staging buffer. A replaced mesh's old buffers are freed once the frames using them have finished |
| A new font size | a size's glyph atlas starts at 256² and doubles when full |
| Freeing big object graphs | a removed component's value moves (as raw bytes, no reference-count change) into its column's buried buffer, and each tick frees at most `app.release_budget` (4,096) of them |
| Spawning many entities | a spawn copies each inline component straight from its bundle into the column, and a flush that applies 4,096 changes or more has the allocator merge the blocks it freed (the bundles) before it returns, so their cost lands in that flush and not in a later tick |
| Despawning many entities | removal records are per column in raw memory (a tick-ordered log and a per-entity "last removed" stamp, so `Removed<T>` checks are one read and trimming is O(trimmed)), and each column removes the whole despawn list in one call. Despawning 200,000 entities of 4 components in one tick takes about 22 ms |
| Opening the cache | `store.bin.index` mirrors every record (key, offset, length), so opening the store is one read |
| Re-cooking a changed source | recipes re-run on a worker, and the engine checks its loaded textures on another; the worst tick while a texture is re-cooked and reloaded is 2 ms |

## Thread affinity

Only where the data says so. A component that declares `pinned_to_creating_thread()` (the window's `Handle`) keeps
the systems that touch it on the app's thread; Vulkan has no thread affinity, so drawing runs on the pool. Every
other system runs on the thread pool, and when no system of a stage is pinned, the app's thread runs one of them
instead of waiting idle ([ecs.md](ecs.md#components-pinned-to-a-thread)).

---

Next: [Testing](testing.md), every example and what it proves.
