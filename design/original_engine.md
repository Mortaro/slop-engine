# The original, hand-optimised engine: what it did, and the numbers to beat

On 2026-10-09 the naive engine became the main branch. The hand-optimised engine it replaced is kept, unchanged,
at the tag `original-hand-optimized` (main at `4ad2129`). This page says what that engine did by hand, what the
naive engine does instead, and the numbers the language must beat, so it stays a target.

The rule from here on: the engine stays naive. Every speed the original had by hand must come from the Spite
compiler, never from the engine's code (decisions D506, D550 and D557 in the language's design/decisions.md).

## What the original did by hand, and what the naive engine writes instead

| Area | Original, by hand | Naive |
|---|---|---|
| Systems of a stage | a `Parallel` per system, two on two threads | one after another; the compiler now runs independent ones at once |
| The runner | hand paths per row shape (Stream, clocked rows, pairs) | one plain loop over the matched rows |
| Columns | a raw 64-byte header with magic offsets, `Items<T>` stored inline, swap-remove | a plain `ColumnIndex` class and a plain `List<T>` per column |
| Freeing | a release budget of 4096 a tick, then the allocator forced to settle | freed when removed |
| Commands | per-thread command queues, a locked id counter, `ThreadLocal` | one command list |
| IO systems | a `Concurrent` worker per IO wait, drained up to 8 a frame | a plain call; the compiler starts the wait and collects it later |
| Navigation | a pool of 32 searchers with their own 4-million-cell scratch, batch sizes | one plain job and one search kept by its owner |
| Physics | colliders as slots in parallel float arrays, tombstones and stamps | colliders as objects |
| Texture compression | bands per level | one plain call per level |
| Network dials | a `Parallel` per connection | a plain call |
| Bytes and tables | `Asset.Bytes` as a malloc'd address with capacity, `Raw` reads and writes at an address, `heap.allocate`d tables in the zstd, PNG, PSD, texture compression and network code, `raw.copy` between them | `Asset.Bytes` keeps a plain `List<Byte>` and reads and writes numbers by position; tables are `List<Integer>`; a copy is `write_bytes(source, start, count)`; mapped GPU memory is written through `ForeignBytes` (`store_at`) |
| File watching | `Recipes.Watcher` with `inotify` and `ReadDirectoryChangesW` bindings per operating system, a hand settle time, buffers from `Memory.Heap` | the library's `FileSystemWatcher`; the file lock between processes (`Recipes.StoreLock`) stays, the library has no such lock |
| Matrix products | `set_product`, `copy_from` and a flat-float `set_product_with_values` reopened into the library's `Matrix4`, to multiply in place | `a * b` of the library, a fresh matrix each time; a copy is `a * Matrix4<Float>()` |

The full history, gap by gap with the measurements of each step, is in [naive_baseline.md](naive_baseline.md).

## Not converted yet

Asset loading still uses `Parallel`; the reused `_all` row objects, and the generation stamps in navigation and
contacts remain. See naive_baseline.md, "What is not converted yet".

Still on hand memory (`Raw`, `Memory.Heap`, `TypedMemory`), waiting for the language's plain foreign structs:

- the Vulkan bindings (`render_vulkan/renderer.spite`, `structure.spite`, and the scene_vulkan passes: grass, mesh,
  occlusion, post process, shadow, terrain, water), the Windows plugin (`pump_messages`, `track_window_size`,
  `window_class`), the XInput `poll_gamepads`, and the `OVERLAPPED` struct of `os/windows/recipes/store_lock.spite`
  (written through `ForeignBytes`; the library has no lock between processes, so the file lock stays);
- `Matrix4.write_to` in `slop/matrix4.spite` and `Raw` in `slop/raw.spite`, which only those bindings use;
- tables the render code keeps for the GPU: `render/component/draw_list.spite` (rectangle records), the software
  renderer's `canvas.spite` pixels and `present.spite` bitmap header, and `scene/light_clusters.spite`, which writes
  cluster ranges straight into mapped memory;
- `ui/fonts.spite` stages the cooked font in a heap block because the `spite_truetype` package's
  `FontData.copy_bytes` takes a `Memory.Address`; it needs to take a `List<Byte>`.

## The numbers to beat

Quiet measurement, 2026-10-09, Spite compiler `579d35c5`, `--optimized --build`, Ryzen 9 5950X, medians of 5
rounds alternating original and naive (from the language's design/naive_programs.md, "Quiet measurement"):

| Benchmark | Original (target) | Naive at the switch |
|---|---|---|
| stress tick | 5,953 µs | 24,180 µs (about 10,900 under load after per-object facts, D555 and D556) |
| stress despawn, sixty ticks | 23,915 µs | 20,909 µs |
| physics step | 5,691 µs | 6,941 µs (6,955 against 5,869 after the physics pass, D552 and D553) |
| physics MoveCharacters | 4,966 µs | 5,692 µs |
| physics SortColliders | 275 µs | 688 µs |
| physics ReadCharacters | 179 µs | 362 µs |

Earlier figures for animation, replication and navigation (equal or naive faster) are in naive_baseline.md. By hand,
splitting each system's loop into chunks on every core gave a stress tick of 5.5 ms against the original's 6.6 under
the same load: the target is to beat the original by a wide margin, not to match its two threads (D557).
