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
- Stage 1b (the plain runner and plain lists, below): 2026-10-07 again, Spite at `a3459207` (the compiler had not
  moved for these programs), the machine shared with one other build; stress and physics only, the stage 1 build
  (`50e8d79`), `48f81d0` and `0c2c278` run interleaved, 5 rounds, medians. The stage 1 build measured 25.3 ms a
  stress tick in this round against 27.3 ms in the first, so compare numbers within a round.
- Not measured: `render_bench` and `props_bench` do not build with today's compiler on `main` either (the
  `spite_truetype` package at `4963d04` trips the new "declared only to be returned" rule), and both need a GPU
  window.

## The table

| Benchmark (what is timed) | Hand | Hand runs in parallel? | Naive | Naive / hand |
|---|---|---|---|---|
| `stress`: tick, 200,000 entities, `Move` and `Regenerate` | 7.0 ms | yes: 2 systems on 2 threads, 1.6 cores (12.8 ms with `--parallel=false`) | 27.3 ms; with the plain runner and lists (`0c2c278`) 112.1 ms | 3.9x slower; now 16x |
| `physics_bench`: tick, 5,000 characters, 10,000 boxes | 6.4 ms | no: 1.1 cores, systems conflict and run one by one | 9.8 ms; with the plain runner and lists 16.1 ms | 1.5x slower; now 2.5x |
| `navigation_bench`: one thread, goals within 125 cells | 10,761 queries/s | no | 11,905 queries/s | same (same code) |
| `navigation_bench`: one thread, goals within 600 cells | 639 queries/s | no | 700 queries/s | same (same code) |
| `navigation_bench`: 20,000 queries in batches | 2,533 queries/s on 32 threads, 28 cores busy | yes, and 4.2x slower than its own one-thread run | 11,882 queries/s in one job | 4.7x faster |
| `navigation_bench`: 10,000 bots ask at once, all answered | 3,811 ms over ~4,600 ticks, worst tick 186 ms | yes (`RequestPaths` batches on the pool) | 890 ms over 2 ticks, worst tick 856 ms | 4.3x faster to answer, 4.6x worse worst tick |
| `animation_bench`: `Animate` over 2,800 animators | 17.2 ms | no: 1.1 cores | 17.5 ms (not rerun since `Animate` lost the pair path) | same (within noise) |
| `replication_bench`: `Send` per tick, 10,000 mirrored | 804 µs | no: 0.4 cores (paced at 16 ms) | 801 µs | same |

Where each commit moved it (medians, µs):

| Benchmark | Hand | Threads removed (`59fa628`) | + plain columns, IO drain, dials, navigation (`271cd9b`) | + physics objects, textures (`7e10761`) | Stage 1b round: `7e10761` again | + one plain loop per system (`48f81d0`) | + every column a `List<T>` (`0c2c278`) |
|---|---|---|---|---|---|---|---|
| `stress` tick | 7,000 | 13,295 | 27,148 | 27,312 | 25,251 | 99,413 | 112,121 |
| `stress` `Move` / `Regenerate` | 6,600 / 6,352 | 6,868 / 6,403 | 10,641 / 17,312 | 10,405 / 17,110 | 10,751 / 14,540 | 47,922 / 51,024 | 55,100 / 56,988 |
| `stress` despawn: sixty ticks | 22,757 | 22,210 | 54,832 | 55,412 | 59,900 | 59,146 | 143,439 |
| `physics_bench` tick | 6,374 | 6,298 | 6,926 | 9,798 | 10,700 | 15,657 | 16,108 |
| `physics_bench` `SortColliders` / `MoveCharacters` / `ReadCharacters` | 349 / 5,101 / 210 | 362 / 5,126 / 195 | 383 / 5,428 / 324 | 1,428 / 6,847 / 479 | 1,608 / 7,564 / 547 | 1,611 / 10,480 / 1,566 | 1,819 / 10,786 / 1,677 |
| `navigation_bench` batch | 2,533 q/s | 2,636 q/s | 10,356 q/s | 11,882 q/s | not rerun | not rerun | not rerun |

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

Beyond that the real prize is **T1** inside one system: the runner's `while combination < total` over 200,000
matched rows (the `Stream.run_positions` loop until `48f81d0`) has a body that writes only its own row's items and
stamps that row's entity.
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
whose callers are in other units next to them, or emit it `static inline` in the header. Gap 4 below found which
calls they are and measured the fix; it is a new pair, C6.

### 4. The unexplained 4 ms: `Regenerate`'s match landed in a unit without the release (stress 6 ms, explained)

Measured on the stage 1 build (`50e8d79`), where both systems ran through `Stream`: `Move` 10.7 ms, `Regenerate`
17.2 ms in the split build. Built as one C file (`SPITE_TRANSLATION_UNITS=1`), the same program gives `Move` 11.8 ms
and `Regenerate` 11.5 ms: the whole difference is where the unit split put the functions, not anything
`Regenerate` does that `Move` does not. Its C is the same as `Move`'s token for token (`find_row`, `match_into`, the
stream loop, renamed).

The per-entity call that matters is `Row.find_row`, run once per row field per entity. Its body reads
`headers[index]` twice (a `crash` narrowing and a local), so it calls `ColumnIndex___release` four times per entity,
and calls `List_Integer_get_at` and `List_Integer_set_at`. The split build puts each function in the unit its name's
hash picks: `Move`'s `find_row` landed in the unit that defines `ColumnIndex___release`, `List_Integer_get_at` and
`List_Integer_set_at`, so the C compiler inlined them before linking; `Regenerate`'s landed in another unit, and
thin LTO then refused to inline `ColumnIndex___release` (its cost is 665 against a threshold of 225, because the
function also holds the freeing path: five releases of its lists and the free), so every one of those is a real
call around an atomic decrement. Clang's inlining remarks at link time (`/mllvm:-pass-remarks-missed=inline`) show
it: `ColumnIndex___release` "not inlined" seven times into `Regenerate`'s `find_row` and never into `Move`'s.

Hand-edited C, the same four units rebuilt with the same flags, 5 runs each:

| Build of the stage 1 `stress` | tick | `Move` | `Regenerate` |
|---|---|---|---|
| units as generated | 28.0 ms | 10.7 ms | 17.2 ms |
| `Regenerate`'s `match_into` moved into the stream loop's unit | 27.7 ms | 10.7 ms | 17.1 ms (no change) |
| `Regenerate`'s `find_row` moved into the unit with the release and the list accessors | 22.8 ms | 11.5 ms | 11.2 ms |
| units as generated, `ColumnIndex___release` split: a `static inline` decrement in the header, the freeing out of line | 23.0 ms | 10.4 ms | 12.6 ms |
| one C file | 23.5 ms | 11.8 ms | 11.5 ms |

Proposed pair **C6, a release is inlined everywhere**: the generator emits each class's `___release` as a
`static inline` decrement and test in the header, calling an out-of-line function only for the free, and does the
same for the small list accessors (`get_at`, `set_at`, `count`) that every unit calls. Proof: none; it is a code
generation rule (the fast path is the same code in every unit). It is C4 made specific: a function is inlined
across units when its common path is small, even if its rare path is not. What is left after the release split
(12.6 against 11.2 ms) is the list accessors. In the current form (`0c2c278`) the split costs less in proportion
(112.1 ms in units, 101.2 ms as one file), but the same calls are in every per-entity path.

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

### 10. One plain loop per system instead of hand paths by row shape (stress 25.3 ms becomes 99.4 ms; physics 10.7 becomes 15.7)

`48f81d0` removed the runner's hand paths: `Stream` (a one-row system walking the driver column and borrowing inline
items in place), the clocked row (the game clock filled once beside a streamed row) and the pair path (the smaller
row outside, the larger streamed inside). Every `_each` system now gathers each row's matching entities
(`row.candidates()`), loops over their combinations, fills each row (`row.fill`), calls the system and stores the
row back (`row.store`). A link in the first row still names the second row's entity (`run_related`): that is what a
link means, not a shape. Per entity and tick, against `Stream`, the plain loop:

- **copies each inline item to the heap and back**: `Slot.fetch` read `Column.value_at`, which returned
  `values[row].copy()`, a `malloc` and later a `free` per component per row (800,000 of each per stress tick), and
  `store` wrote the copy back with `values[row] = value`. Proposed pair **B2, a copy written back to where it came
  from is the item itself**: a value copied out of a list slot, and written back to the same slot, with nothing
  else reading or writing that slot in between, is the slot borrowed in place; no copy, no write-back. Proof: the
  effect summary of the code between the copy and the write-back (the system's phase function) touches the slot
  only through the copy. It is what `Stream` did by hand. Falls back: the copy.
- **matches each entity twice**: `candidates()` runs `matches` to build the list and drops the row positions it
  found; `fill` runs `matches` again to find them (a `crash found` that also fills `rows`). Proposed pair **L8, a
  list built by one loop and read once in order by the next is fused into one loop**: the producer's per-item work
  and the consumer's run in the same pass, the list is never built, and what the consumer recomputes from the item
  (here the match) is the producer's value. Proof: the list is local to the function, read only by the consuming
  loop in index order, and nothing in the consumer writes what the producer read (a system never writes column
  membership; that changes only at the flush). It generalises the built "template chains run as one loop" from
  library templates to any two loops. Removing the second match alone is not possible by hand: it is where the row
  positions come from (replacing it by `true` in the C crashes, as it should).
- **counts every reference atomically and enters a guarded singleton per call**: rows, `Row<T>`, `Slot<T>`,
  `Column<T>` and the row `type` objects are retained and released through `SPITE_COUNT_UP`/`DOWN`, atomic because
  asset loading starts threads; each `Row<T>` call also tests `spite_tasks_in_flight` atomically. Measured on the
  `0c2c278` one-file C with plain counts and nothing else changed: 101.2 ms becomes 65.6 ms, the largest single
  item. Pairs **C5** (plain counts for a class no task reaches) and **B1** (a borrowed read), now measured.
- **builds a candidate list per row per tick** (a fresh `List<Integer>` of 200,000): L8 removes it; without L8,
  **L6** (keep the storage of a list cleared and refilled every tick).

Physics lost less (10.7 to 15.7 ms) because its hot systems do real work per row; `ReadCharacters` (547 to
1,566 us) and `MoveCharacters` (the former clocked row, 7.6 to 10.5 ms) carry the same per-row costs.

### 11. Every column a `List<T>` (stress 99.4 ms becomes 112.1 ms; despawn 59.1 becomes 143.4 ms; physics 15.7 becomes 16.1)

`0c2c278` replaced `Items<T>` (inline, contiguous, chosen at compile time by `fits_vector`) by one `List<T>` for
every component. Rows and lookups now hold the stored objects, so B2's copies are gone, but every component is its
own heap object: each fetch is a pointer to follow and an (atomic) retain and release, and despawning 200,000
entities frees 800,000 objects at the flush (sixty ticks 59.1 become 143.4 ms). Pair **L1** applies directly: a
`List<T>` whose items have no identity outside it (every reference to a component is a row or a lookup that ends
with the call) is stored as the items themselves, contiguous, as `Items<T>` did by hand; then the frees are one
block's. Proof: no reference to an item escapes the call that read it (the row's objects are refilled every
entity; `Lookup.of` returns it to a caller that may keep it, which is the escape to prove absent). Falls back: the
list of objects. **M3** spreads the remaining frees if they still show.

Three behaviours the change makes visible, all for Mortaro:

- A component that fits a `Vector` is copied when it is added (`Column.insert_object`), so a caller's object stays
  its own, as it was with `Items<T>`. With a list of references that copy is now a rule of the engine, not a side
  effect of the storage.
- `Lookup.of` no longer lends a borrowed item, so `var layout = lookup.of(entity)` followed by `layout = made`
  compiles and changes nothing stored: a silent lost write (D244) that `Items<T>`'s borrow rule refused, and that
  reference-stored components always had. The language needs the borrow rule for a reference read from a list too,
  or the engine a writer API that makes the replacement impossible.
- An IO system still may not write a component that fits a `Vector` of its rows (`snapshot_write_refused` passes),
  but the reason ("the row holds a copy") is gone: the row now holds the stored object, as for every other
  component. Whether the rule stays is Mortaro's decision.

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
- **The `_all` row objects** kept in `Row.pooled_rows` and refilled each run: a hand reuse of objects (a list
  system allocates its list and nothing per row). The plain form makes a fresh row per entity; that needs M1 (a
  frame arena) or L6 to cost nothing, not done.
- **Generation stamps** in `Navigation.Search` and `Physics.Contacts`, and the last-pose memo in `Animate`: these are
  algorithms more than hand placement; rewriting `Search` to clear its four-million-cell tables per query would
  make each query cost the whole grid, so it needs L6 (a cleared list read only after it is written) first.
- **`Recipes.StoreLock`**: an operating-system file lock between processes, not a thread lock.

## Checks after stage 1b

Every headless check listed above gives the same output after `48f81d0` and after `0c2c278`, except counts that
depend on timing and differ between two runs of the same build too: `animation_check`'s skipped throttle ticks (14,
15 or 21, from the tick its assets land), `replication_check`'s "busy one", `unreliable_check`'s datagram count and
`clock_check`'s game times. `snapshot_write_refused` still refuses. One deliberate change: a waiting (IO) system
that writes a row now stamps the row's entities written when they are queued, whatever its row count; before, only
a one-row waiting system did (through the stream's write-back), and a waiting system of several rows wrote without
`Changed<T>` seeing it, which was silent.

## Branch state

`naive` on origin, 13 commits over `main`: `5d84fba` (physics hash fix), `59fa628` (stages in order, one command
list), `596b4c7` (plain columns), `8f952d8` (IO drain), `379fa26` (dials), `205e64c` (navigation), `271cd9b`
(format), `7399f59` (physics objects), `13767c1` (checks), `dbaaf4d` (decoder fix), `9f2b87a` (textures),
`7e10761` (docs), and this report (`50e8d79`); then stage 1b: `48f81d0` (one plain loop per system),
`0c2c278` (every column a `List<T>`) and its report.

## 2026-10-09: first measurements on the new compiler (provisional)

Provisional: measured while the machine was in other use, so single runs swung by up to 25%; a quiet re-timing
will replace these numbers. Compiler: Spite at `f5fdd667`, the first that requires `Dictionary<Key, Value>` and reads
files and sockets through a `List<Byte>`. Hand: `main` at `346efda`; naive: `naive` at `b53451c`. Both branches
changed only what that compiler needs to build them: every dictionary names the key the old compiler inferred, and
`Asset.Bytes`, the recipe store and records, and the network channel copy through `ForeignBytes` at the file and
socket edge. `--optimized --build`, 5 rounds run interleaved hand/naive, medians (lowest to highest in brackets),
microseconds.

| Benchmark | Hand | Naive | Naive / hand |
|---|---|---|---|
| `stress` tick | 8,312 (6,811 to 8,909) | 32,278 (29,297 to 38,104) | 3.9x slower |
| `stress` `Move` / `Regenerate` | 7,792 / 7,555 | 16,142 / 16,108 | 2.1x slower each |
| `stress` despawn: sixty ticks | 27,371 | 25,067 | same |
| `physics_bench` tick | 8,301 (7,117 to 9,935) | 12,064 (11,181 to 14,321) | 1.5x slower |
| `physics_bench` `SortColliders` / `MoveCharacters` / `ReadCharacters` | 355 / 7,049 / 278 | 1,369 / 9,276 / 714 | |

Naive `stress` went from 112.1 ms a tick (`0c2c278` on the stage 1b compiler) to 32.3 ms, and its despawn from 143.4
to 25.1 ms, with no change to the engine's code beyond the two migrations: the gain is the compiler's (the loop bands
and the other optimisations since `a3459207`), to be confirmed by the quiet re-timing.

Every headless check listed above builds and passes on both branches. Against the same programs built with the
compiler before the change (`8dbdd4e5`), the outputs are the same except for counts that depend on timing
(`animation_check`'s skipped throttle ticks and unseen time, `clock_check`'s game times, `unreliable_check`'s
datagrams, `replication_check`'s busy count, `navigation_check`'s arrival tick on `main`, and the timings that
`relations_check`, `stream_bench` and `timers_check` print) and one printed float: `navigation_check` on `naive`
prints the gentle ramp's height as `1.746` where the old build printed `1.7460002`. `texture_compression_check` and
`interest_check` compile again. Every example that loads `spite_truetype` (`4963d04`: the UI plugin, and through it
every windowed example) or `spite_mongodb_driver` (`fd2aa14`: `io_systems`, `mongodb_check`) still does not compile:
those packages read files and sockets through addresses and trip the "declared only to be returned" rule, and they
live in their own repositories.

Both packages are migrated in their own repositories (`spite_truetype` `6c7b076`, `spite_mongodb_driver`
`fbb6653`: byte lists through `ForeignBytes`, locals returned directly) and the engine pins them. Every example
now builds on both branches except the two that must fail to compile (`list_component_refused`,
`snapshot_write_refused`). On `naive`, the
scene's occlusion pass lost an attribute it never read, which the compiler refused once the UI plugin compiled
again. `mongodb_check` prints `accounts 1 passed true` on both branches. `io_systems` passes on `main` (31 frames
while waiting) and fails its own check on `naive` (3 frames): the naive runner drains an IO system's rows between
frames with a plain call (`8f952d8`), so frames no longer advance while the lookups wait, and the example's
`frames > 10` check predates that.

The engine no longer carries a database (2026-10-09, Mortaro: storage is the game's): `slop_mongodb_plugin` and
`mongodb_check` are removed, and `io_systems` waits on record files the program writes before the app starts (a
200 ms sleep, then a file read, per lookup) instead of MongoDB queries. It passes on `main` (29 frames while waiting,
balanced) and still fails its `frames > 10` check on `naive` (3 frames, every lookup finished at frame 2), for the
reason above: the naive runner drains IO systems with a plain call, and the check passes again once the compiler
arranges the wait (the language's W1). Every other example builds on both branches with Spite master `8ba6a9fa`, the
two refusals excepted, and the headless checks pass on `naive` balanced under `--debug-memory`, including
`list_component_refused/test.sh` once its expected text names `Dictionary<String, Integer>`.
