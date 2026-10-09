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
| Matrix products | `set_product`, `copy_from` and a flat-float `set_product_with_values` reopened into the library's `Matrix4`, to multiply in place | `a * b` of the library, a fresh matrix each time; a copy is `a * Matrix4<Float>()` |

The full history, gap by gap with the measurements of each step, is in [naive_baseline.md](naive_baseline.md).

## Not converted yet

Asset loading still uses `Parallel`; the Vulkan, Windows and XInput bindings still use `Memory` for structs (the
language's plain foreign structs are decided, not built); a few byte tables, the reused `_all` row objects, and the
generation stamps in navigation and contacts remain. See naive_baseline.md, "What is not converted yet".

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
