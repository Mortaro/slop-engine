# The naive engine against the hand-optimised one: stage 1 baseline

Stage 1 of the language's plan for naive programs (`SpiteLanguage/design/naive_programs.md`): the engine's hand
optimisations rewritten as plain lists, loops, classes and calls on this `naive` branch, measured against `main`
with the same compiler, so that every gap becomes a pair (an optimisation and the proof it needs) in
`SpiteLanguage/design/naive_programs_pairs.md`. Everything in the "Proposed" columns is proposed by Claude,
unconfirmed.

## How it was measured

- Machine: AMD Ryzen 9 5950X (16 cores, 32 threads), 32 GB, Windows 11, shared with other work (a language
  `check.sh` ran during part of it, so single runs swing by up to 15%).
- Compiler: Spite at `e7261193`, through `bin/spite <bench> --optimized --build`, clang from Visual Studio 2022.
- Hand: `main` (`4e13dbc`) plus the two fixes today's compiler needs (`5d84fba`: physics hashed a negative cell into
  an `UnsignedInteger` and halted; `dbaaf4d`: a lint in the texture decoder). Naive: `naive` at `7e10761`.
- Each benchmark ran 5 times (3 for the intermediate commits), stress and physics again 5 times interleaved
  hand/threads/storage/naive; the tables give the median. Threads: a sampler read each process's thread count and
  CPU time every 20 ms; "cores" is the highest CPU time over wall time in any 200 ms window.
- Not measured: `render_bench` and `props_bench` do not build with today's compiler on `main` either (the
  `spite_truetype` package at `4963d04` trips the new "declared only to be returned" rule), and both need a GPU
  window.

## The table

| Benchmark (what is timed) | Hand | Hand runs in parallel? | Naive | Naive / hand |
|---|---|---|---|---|
| `stress`: tick, 200,000 entities, `Move` and `Regenerate` | 7.0 ms | yes: 2 systems on 2 threads, 1.6 cores (12.8 ms with `--parallel=false`) | 27.3 ms | 3.9x slower |
| `physics_bench`: tick, 5,000 characters, 10,000 boxes | 6.4 ms | no: 1.1 cores, systems conflict and run one by one | 9.8 ms | 1.5x slower |
| `navigation_bench`: one thread, goals within 125 cells | 10,761 queries/s | no | 11,905 queries/s | same (same code) |
| `navigation_bench`: one thread, goals within 600 cells | 639 queries/s | no | 700 queries/s | same (same code) |
| `navigation_bench`: 20,000 queries in batches | 2,533 queries/s on 32 threads, 28 cores busy | yes, and 4.2x slower than its own one-thread run | 11,882 queries/s in one job | 4.7x faster |
| `navigation_bench`: 10,000 bots ask at once, all answered | 3,811 ms over ~4,600 ticks, worst tick 186 ms | yes (`RequestPaths` batches on the pool) | 890 ms over 2 ticks, worst tick 856 ms | 4.3x faster to answer, 4.6x worse worst tick |
| `animation_bench`: `Animate` over 2,800 animators | 17.2 ms | no: 1.1 cores | 17.5 ms | same (within noise) |
| `replication_bench`: `Send` per tick, 10,000 mirrored | 804 µs | no: 0.4 cores (paced at 16 ms) | 801 µs | same |

Where each commit moved it (medians, µs):

| Benchmark | Hand | Threads removed (`59fa628`) | + plain columns, IO drain, dials, navigation (`271cd9b`) | + physics objects, textures (`7e10761`) |
|---|---|---|---|---|
| `stress` tick | 7,000 | 13,295 | 27,148 | 27,312 |
| `stress` `Move` / `Regenerate` | 6,600 / 6,352 | 6,868 / 6,403 | 10,641 / 17,312 | 10,405 / 17,110 |
| `stress` despawn: sixty ticks | 22,757 | 22,210 | 54,832 | 55,412 |
| `physics_bench` tick | 6,374 | 6,298 | 6,926 | 9,798 |
| `physics_bench` `SortColliders` / `MoveCharacters` / `ReadCharacters` | 349 / 5,101 / 210 | 362 / 5,126 / 195 | 383 / 5,428 / 324 | 1,428 / 6,847 / 479 |
| `navigation_bench` batch | 2,533 q/s | 2,636 q/s | 10,356 q/s | 11,882 q/s |

Every check still passes and prints the same results (`healing`, `tracking`, `changed_check`, `without_check`,
`use_potion`, `relations_check`, `timers_check`, `inline_string_probe`, `asset_round_trip`, `attachment_check`,
`animation_check`, `physics_check` byte for byte, `navigation_check`, `wire_probe`, `scheduler_check`,
`stream_bench`, and the `parallel_check`, `replication_check`, `unreliable_check`, `clock_check` and
`handshake_check` scripts). What moved is only how many ticks an asynchronous result takes to land: a search, a
dial or an IO system's answer now lands in the tick that asked, so `navigation_check` arrives after 86 ticks instead
of 87, `scheduler_check` finishes at frame 8 instead of 9 and `attachment_check` places its sword after 4 ticks
instead of 5. `texture_compression_check` and `interest_check` fail on `main` and `naive` alike, in the compiler (see
the language gaps).

## Gaps, ordered by the time they cost

### 1. Two systems of a stage no longer overlap (stress: 6.3 ms of 7.0, top priority)

Hand: `App.run_stage` starts every system of a stage but one as a `Parallel` and runs the last itself. Naive: the
stage is a plain loop, `stage.each(run_runner)`, over a `List<Runnable>` built in `App()`. `Move` writes only
`Position`, `Regenerate` only `Health`; nothing written is shared.

The compiler leaves it serial because D505 only overlaps a written row of calls (`a.f()` then `b.g()`), and this is a
loop over interface values. Proposed pair **T4b**: *a loop over a list of interface values that is never changed
after it is built, whose elements are made from a compile-time set of classes (`Runner<system.class>` for each
`Symbol<System>`)*: unroll it into the row of calls it always makes, then apply D505 per pair. Proof: the list is
written only in the constructor (`App()`, `build_phase`), every element's class is known, and each pair's effect
summaries (stage 2 of the plan, per field) are disjoint. Today the stage composition is itself computed at run time
from `reads`/`writes` strings, so the stronger form is for the compiler to derive the stages: the engine would then
only say the order of phases.

Beyond that the real prize is **T1** inside one system: `Stream.run_positions` is a `while position < end` over
200,000 rows whose body writes only its own row's items and calls `note_written`, which stamps that row's entity.
Proof needed: each iteration writes only `Column<T>.values[row]` for its own row and `stamps[entity]` for its own
entity (the driver column maps rows to distinct entities), and reads nothing another writes. Every system of every
benchmark here is this loop; the hand engine never had it ("Parallel iteration inside one system: not built").

### 2. Reading an object out of a list counts a reference, atomically (stress about 5.5 ms; physics about 1 ms)

The naive column bookkeeping is a `ColumnIndex` object per class, kept in `Row<T>.headers: List<ColumnIndex>`. Each
`find_row` per entity per component does `crash headers[index]` (a `get_at` that retains, tests and releases) and
`var header = headers[index]` (a retain, released at every return), where the hand code read a `Long`. Because
asset loading still uses `Parallel` (language gap 1), the program defines `SPITE_THREADS` and every count is an
atomic read-modify-write. Measured by recompiling the generated C of naive `stress` with plain counts and nothing
else changed: 22.5 ms becomes 17.0 ms; `physics_bench`'s `MoveCharacters` 7.8 ms becomes 6.8 ms.

Proposed pairs: **B1, a borrowed read**: a value read from a list into a local, or narrowed in place, takes no
reference while the list is not written and the slot not replaced before the local's last use (here `headers` is
written only in `prepare`). Proof: the effect summary of everything between the read and the last use writes
neither the list nor its element slot. **C5, plain counts for a class no task can reach**: a class whose objects
never reach a `Parallel`, a `Concurrent` or a value another thread can read counts with plain arithmetic even in a
program with threads. Proof: escape analysis from every task's captured values (D474's analysis turned towards
tasks).

### 3. The split build does not inline the small plain-class calls (stress about 5 ms)

The same naive `stress` C built as one file with `clang -O3` ticks in 22.5 ms; Spite's own `--optimized` build
(units and thin LTO) ticks in 27.3 ms. The hand form is the same either way (6.7 ms both). The difference is the
calls the naive form adds: `ColumnIndex_row_of`, `entity_at`, `List_ColumnIndex_get_at`. Pair **C4** (a call to a
small function is inlined) applies, and it has to hold across units: the generator should keep a small function
whose callers are in other units next to them, or emit it `static inline` in the header.

### 4. What is left of the stress gap after 1 to 3 (about 4 ms, not explained yet)

With plain counts the naive tick is 17.0 ms against the hand form's 12.8 ms on one thread. `Regenerate` lost far
more than `Move` (6.4 to 17.1 ms against 6.9 to 10.4 ms) although both stream two inline components; I did not find
why in the generated C in the time I had. Candidates, each with its pair: the nullable `List<Integer>` reads
(`rows[entity]`, `stamps[entity]`) that test `has_value` after a proven bound (C2, a proven read reads unchecked),
the `crash keys[index]` narrowing that retains and releases a `String` per entity (B1), and the stamp written per row
through `while stamps.count() <= entity` before `stamps[entity] = value` (the loop's bound is proven by the column
having grown at insert: a hoisting proof).

### 5. Despawning 200,000 entities (stress: sixty ticks 22.8 ms become 55.4 ms)

Hand: a removal log in raw memory, compacted in place, and removed components moved into a buried buffer freed 4,096
a tick. Naive: a `List<Removal>` of small objects (one allocation per removal), a trim that copies what is kept, and
components let go at once. Pairs: **L1** (a list of small objects with no identity outside it stored as one array per
field, which removes the per-removal allocation), **L5** for the swap-removals, and **M3** (frees of a batch spread
between passes) if the freeing itself shows; separating the two needs `--debug-memory` counts, not done yet.

### 6. Physics: a scratch list per bucket, rebuilt every tick (physics 1.1 ms)

Hand: the grid is a counting sort into three flat lists, cleared and refilled each tick, so no allocation. Naive:
`Physics.Grid` keeps a `List<List<Physics.Collider>>`, and `build` makes a fresh list per bucket every tick for the
character grid (several thousand lists). `SortColliders` went from 0.35 to 1.43 ms. Pair **L6** extended to nested
lists: a list cleared and refilled every tick keeps its storage and its inner lists' storage (here `buckets.clear()`
followed by appending fresh empty lists of the same count), or **M1**, those lists in a frame arena reset when the
tick ends. Proof for L6: nothing reads an inner list after `clear()` before it is refilled, and no reference to an
inner list escapes the grid.

### 7. Physics: a shape returned by a function is copied to the heap (physics about 0.6 ms)

`Collider.seen_from(origin)` makes a `Physics.Shape`, moves it and returns it, 15,262 times a tick. The generated C
builds it in the frame and then allocates a heap copy to return it (`Physics_Shape___allocate()` plus
`___copy_fields`), although every caller keeps it in a local that never escapes. The hand code filled one scratch
`target` shape kept on the singleton. Proposed pair **M5, a returned object lives in the caller's frame**: when every
caller's result never leaves the caller (placement's frame proof applied at the call site), the callee writes into a
slot the caller provides. The same pair would retire the engine's scratch shapes, matrices and rows in general.

### 8. Physics: objects instead of parallel float arrays (physics about 0.3 ms in `ReadCharacters`, the rest of `MoveCharacters`)

Hand: each collider's shape as 24 floats at `slot * 24`, its bounds as 6 at `slot * 6`, kinds, flags and owners in
parallel lists. Naive: a `List<Physics.Collider>` of objects, each holding a `Physics.Shape`. `ReadCharacters` went
from 0.21 to 0.48 ms and the broad phase of `MoveCharacters` reads bounds through two pointers. Pair **L1**: the
colliders have no identity outside `Colliders` (they are kept by `all`, the membership lists, `owned` and the grid,
all inside the singleton), so the compiler may store their fields per array; it needs the "no reference escapes the
class" proof to cover references held in several lists of the same owner. **L2** then groups the six bounds fields,
which every query reads together.

### 9. Navigation: 10,000 searches in one tick (worst tick 186 ms becomes 856 ms; total 3.8 s becomes 0.9 s)

Hand: `RequestPaths` split the tick's requests into batches of 16 to 128, one `Parallel` each, each thread with its
own `Navigation.Search` in a `ThreadLocal`. Naive: one `SearchJob` over every request, one `Search` kept by
`Searchers`. Answering everything is 4.3x faster (the hand form's 32 searchers each touch their own 4-million-cell
scratch tables, which is also why its 32-thread batch query is 4.2x slower than one thread), but the one tick that
answers 10,000 requests takes 856 ms.

The loop `while index < entities.count() { answer(grid, search, found, ...) }` is independent per request except
for the shared `search` scratch. Proposed pair **T8, scratch privatised per band**: an object every iteration
overwrites before reading (`Search.find` stamps a new generation and clears its heap first) gets one copy per band,
so T1 applies; then **T6** decides bands by cost, where the cost model must count the scratch's footprint (four
million cells per copy), which the hand engine did not and paid for. With T1 at 16 cores the worst tick would be
about 55 ms; spreading the answers over ticks is not something a plain program says (language gap 1).

### Even or better: animation, replication, navigation one-thread queries

`animation_bench`, `replication_bench` and the one-thread navigation queries are the same within noise: their hot
code had no hand threading or layout to lose. Without the per-runner command buffers and the id lock, physics on one
thread is as fast as the hand form (6.30 against 6.37 ms) before its own layout changes.

## Language gaps found while rewriting

1. **Work that may finish in a later frame has no plain form.** Asset loading (`Recipes.AssetSlots`, `Blobs`,
   `Catalog`, `CookRun`, `Render.Textures`, `Scene.Meshes`, `Scene.TerrainMaterials`) starts a `Parallel` and polls
   it each tick, so a frame never waits for the disk. Written plainly (`job.run()` where it is asked for), the
   compiler's wait analysis marks every frame system that may reach a load as an IO system, and the runner then
   refuses `Animate` and `FollowBones`, which write inline components of their rows: the plain form does not compile.
   So these keep their `Parallel`, and because of them every program here defines `SPITE_THREADS` (gap 2 above).
   The language needs either a way to say "this result may arrive later and the frame reads whether it is there"
   without a handle, or a decision that W1 may carry a wait across the passes of a frame loop. Mortaro to decide.
2. **Bytes from files and sockets come only through addresses.** `File.read_bytes(position, count, address)` and
   the socket calls write into a `Memory.Address`, so `Asset.Bytes`, the recipe store and records, and the PNG, PSD
   and zstd decoders' tables stay on `Memory.Heap` and `Raw`. A plain form needs a byte list the library reads into.
3. **A foreign struct that holds a pointer or an array has no plain declaration.** Number-only `type`s cross foreign
   calls; Vulkan's create-info chains, Win32's messages and XInput's state hold pointers to other structs and
   arrays, so the Vulkan, Windows and XInput plugins (nearly 300 `Memory` and allocator uses) stay as they are.
4. **Thread affinity of an operating-system handle is an engine convention** (`pinned_to_creating_thread()`). Once
   the compiler runs systems at once (gap 1 above), it must know that a window handle is used only on the thread that
   made it; that fact belongs to the foreign binding, not to the engine.
5. **Stages are still the engine's.** The naive engine still groups systems into stages from their reads and
   writes, because queued commands are applied between stages and the results depend on where. A fully plain
   engine would apply them after every system, which changes when a system sees another's commands: Mortaro to
   decide whether that is acceptable or whether the compiler should own the stages.
6. **Compiler bugs met on the way** (both on `main` too): the C of a crash report names a local's type as
   `axis_red_ *` (`texture_compression_check`, `TextureCompression.BlockEncoder`) and `across_ *`
   (`interest_check`, `Spatial.Grid`), so those two programs do not compile; and `spite_truetype` at `4963d04` no
   longer compiles under the "declared only to be returned" rule, which keeps `render_bench` and `props_bench` from
   building.

## What is not converted yet

- **Asset loading and cooking** (`Parallel` in 7 files): language gap 1.
- **Vulkan, Windows, XInput** (`Memory.Heap`, `Raw` and Vulkan allocator arguments in about 20 files): language
  gap 3. `RenderVulkan.GpuTimings`' `no_allocator` is a Vulkan argument, not a Spite allocator.
- **Byte buffers and codecs** (`Asset.Bytes`, recipe store, PNG, PSD, zstd tables, the draw list and the software
  canvas): language gap 2 for the file-facing ones; the tables could become `List<Integer>` now, not done.
- **The runner's hand fast paths**: `Stream` (one-row systems borrowing inline items), the clocked row, the pair
  path and the reused `_all` row objects are hand specialisations by row shape; the plain form is the general
  combination path. Not measured yet; it is the next rewrite for `stress`.
- **`Items<T>` in `Column<T>`**: the library's chosen-for-you storage, kept; the plainest form would be a `List<T>`
  and the compiler's L1.
- **Generation stamps** in `Navigation.Search` and `Physics.Contacts`, and the last-pose memo in `Animate`: these are
  algorithms more than hand placement; rewriting `Search` to clear its four-million-cell tables per query would
  make each query cost the whole grid, so it needs L6 (a cleared list read only after it is written) first.
- **`Recipes.StoreLock`**: an operating-system file lock between processes, not a thread lock.

## Branch state

`naive` on origin, 13 commits over `main`: `5d84fba` (physics hash fix), `59fa628` (stages in order, one command
list), `596b4c7` (plain columns), `8f952d8` (IO drain), `379fa26` (dials), `205e64c` (navigation), `271cd9b`
(format), `7399f59` (physics objects), `13767c1` (checks), `dbaaf4d` (decoder fix), `9f2b87a` (textures),
`7e10761` (docs), and this report.
