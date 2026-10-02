# Testing

Every behaviour the docs claim is checked by a program in `examples/`. Run them from `examples/` with
`D:/Projects/SpiteLanguage/bin/spite`; each ends with its memory balance when given `--debug-memory`. Measure
timings only on a production build ([performance.md](performance.md#measure-a-production-build)).

| Program | Proves |
|---|---|
| `click_counter_test` | the whole game through real Win32 messages in a hidden window: 5 (or `--clicks=N`) presses and releases posted to the window, counted by `CountClicks`, shown on the label, and the button left on its hover plate by the style systems |
| `text_field_test` | the text_field game in a hidden window: a click focuses the first field, real `WM_CHAR` and `WM_KEYDOWN` messages edit it to "HEXLL" with the caret at 3, then Tab moves focus to the second field, which receives "Y" |
| `drag_drop_test` | drag and drop on a real window: a drop onto a target (`Dropped` names the source), a drop onto nothing (`DropMissed`), a short drag inside a parent `Button` (no `Clicked` on the parent), a plain click, a right click (`RightClicked`) and a double click (`DoubleClicked`) on the same draggable button; each step waits for the marker it causes |
| `negative_lookup_refused/test.sh` | `Lookup.has(-1)` crashes, naming `looked_up_a_real_entity_not_a_negative_id`, instead of reading out of bounds |
| `combo_box_test` | a combo box on a real window: open it, pick the third option (`selected` 2, label "Third", popup closed), open it again and click outside to close it |
| `scroll_list_test` | the scroll_list game through real Win32 messages in a hidden window: two wheel notches scroll the list by 80, the rows move with it, and a click lands on the row now under the pointer |
| `click_counter_online/test.sh` | a server and three headless bots in separate processes: the first bot joins at 0 and clicks 3 times, the second joins later and sees 3 without clicking, the third sees 3 and makes it 5. Run `bash examples/click_counter_online/test.sh` |
| `hot_reload_test` | a source file rewritten while the app runs is re-cooked on a worker, noticed by the engine's own watch on the cache, reloaded and re-uploaded: the software canvas and Vulkan follow red then blue, and it prints the worst tick meanwhile (2 ms) |
| `live_asset_test` | rewrites the sources of a cooked mesh and a cooked skeleton while the app runs, and waits until both are swapped in (`Meshes`, `AssetSlots` following `Recipes.Catalog`) |
| `store_race_test/test.sh` | four processes append 2,000 records each to one store at once; all 8,000 must read back as themselves |
| `flex_layout` | 92 checks: a screen root with `display: none` paints nothing; flexbox boxes (justify, grow and shrink, alignment, reversal, order, relative and absolute positioning, box model, wrapping), grid tracks, a scrolled and clipped panel, and z-index paint order, each box to 0.01 pixel |
| `render_parity` | Vulkan and the software rasteriser draw the same frame, textured button, alpha edges, a wall of bitmap text and a Cinzel TrueType label (glyph quads from a runtime atlas) included: 0 of 256,000 pixels differ |
| `lights_check` | a red point light and a blue spot light on a dark floor through the clustered shader: the pixel under the point light is lit red and a far corner stays dark; `extra_lights` adds a grid of lights for timing |
| `shadows_check` | sun shadows from a box in each of the three cascades, seen close and from far above: the shadow lands behind each box and reaches its base, its sunny side stays as bright as the open floor, and a shadow edge holds its brightness while the camera moves; then at night a point light's and a spot light's box shadows; `--save-folder=<folder>` saves the three frames |
| `attachment_check` | headless: a bone attachment follows a named bone with an offset, and another follows a bone index, on a synthetic skeleton turned a quarter: both land where the maths says and carry the turn |
| `animation_check` | headless, on a synthetic skeleton: a 50/50 blend of two clips lands on their midpoint (position and rotation) and a 3:1 blend a quarter of the way; a crossfade starts on the first clip, passes through `elapsed / duration` of the way each tick, ends on the second clip with `Crossfaded`, which is gone the next tick; a looping clip wraps at its last key (0.2 s for three keys at 10 per second), a clip with a loop start plays its intro once and loops the rest, and both keep their stored time inside the clip; a throttled animator 200 m away matches an unthrottled one on every tick it is sampled and holds its pose in between, with intervals 1, 2, 4 and 8 by distance; an `Unseen` animator is never posed while its time advances |
| `animation_bench` | headless: `Animate` over 400 seven-part characters (2,800 animators, 65 bones) in rings 4 to 94 m from the camera; prints the microseconds per tick and animators per millisecond, `--throttled=true` for throttled animators; run `--optimized` |
| `inline_string_probe` | inline components holding long text and an enum: `_each`, `_all` and two-row systems, bundle spawns and writes through `Lookup.of` stay balanced under `--debug-memory` |
| `stream_bench` | nanoseconds per row of single-row systems by shape (one inline component, two, `Entity` plus one, inline plus reference) over 100,000 entities; run `--optimized`, and `--parallel=false` for sequential stages |
| `snapshot_write_refused/test.sh` | an IO system that writes an inline component of its row fails to compile, and the error names the writing line |
| `terrain_check` | a cooked two-by-two-tile terrain, its layer array BC1-compressed: each tile's base layer and a painted splat circle land where the ported M_Terrain formula puts them |
| `foliage_check` | a terrain fixture with two grass types and a lake in a basin, ending once its grass and water are drawn and its textures resident: grass stands where its density map's channel says (green), bare terrain stays sand, and the lake draws over the basin (blue); it prints the GPU time of every pass, saves the frame to `--capture=<file.bmp>`, and `--density-percent`, `--width` and `--height` scale it for timing |
| `render_bench` | a fixed daylight scene (48 posed Kal archers, 400 pillars and a ground slab, 64 point lights, the first `--shadowed-lights` (0) of them casting shadows) at 1920x1080 (`--width`, `--height`): once its draws and textures have settled, it averages the GPU time of each pass over `--measured-frames` (200) frames, prints them, and saves the frame to `--capture=<file.bmp>` when given, and the bytes its textures hold beside what RGBA8 with mips would take; run `--optimized` |
| `props_bench` | 17,000 cube props in a grid: prints the frame time and every system above 0.2 ms; run `--optimized` |
| `animate_bench` | 400 seven-part Kal archers (2,800 animators) in rings around the camera, each archer at its own time: prints the frame time and every system above 0.1 ms; run `--optimized` |
| `resize_check` | a hidden window resized, minimised and restored: the swapchain is rebuilt to the new client size, minimised frames are skipped, and presenting resumes at full size |
| `without_check` | a system over `Health` and `Without<Frozen>` heals only entities without `Frozen`, and heals one once its `Frozen` is removed |
| `tracking` | `Added<T>` and `Removed<T>` are each seen exactly once by a system before the change and one after it |
| `changed_check` | `Changed<T>` is seen once by a system before the writes and one after them for a write through a one-row system, a `Lookup`, a replacing `add_component` and a list system; an unwritten component is seen only when it was added, and a system writing what it watches never sees its own write |
| `use_potion` | two linked rows: each potion heals only the hero its `Owner` names, only if that hero is `Alive`, and a replaced component is written back |
| `healing` | headless systems, entity ids in rows, and two independent systems sharing a parallel stage |
| `parallel_check/test.sh` | two systems that only read `Velocity` share a stage, a writer of `Armor` stands alone and the reader after it starts the next stage, and five parallel runs of 20,000 movers over 30 ticks (spawning, despawning, list systems, lookups) end with the same checksum as a serial run |
| `stress` | 200,000 entities through two systems; prints the tick time |
| `asset_round_trip` | an asset class with every kind of field saved and read back through its derived codec |
| `psd_probe` | `buttons.psd`'s layer tree and sizes |
| `interest_check/test.sh` | area of interest across two processes: a bot's view of 100 beacons follows the server's eye (6, then 11), a despawn in view reaches it (10), links travel both ways (`Near` from the server, a message of a `Point` and its `Target` from the bot), and despawning the beacon the stashes are `Near` removes each `Near` on the bot too (9); a `Target` message naming the beacon the server despawned is dropped, and the server judges the valid one after it |
| `relations_check` | `Parent` links set, changed and removed at run time; a two-row system follows 10,000 items' `Parent` to their 1,000 players; a despawn cascades to children; despawning a hunter's prey removes its `Target` in that flush, and a `Removed<Component.Target>` row sees it |
| `list_component_refused/test.sh` | a component holding a `List`, a `Dictionary` or a `Parallel` fails to compile, each error naming the rule and the component |
| `dead_link_refused/test.sh` | adding a link component whose entity is despawned, or left at `Entity()`, crashes naming the rule |
| `replication_check/test.sh` | replication by write across two processes: a gauge the server writes on each of the bot's acknowledgements arrives on every write, one no system writes (but a system reads every tick) arrives once |
| `handshake_check/test.sh` | a build with one more mirrored component is refused by both sides before anything is read, a matching bot is served after it, and two components whose names hash to one message id crash at startup |
| `unreliable_check/test.sh` | a value written every tick travels by datagram, its final value arrives by TCP although datagrams are dropped on purpose, and a forged datagram with an old tick is ignored |
| `clock_check/test.sh` | a bot following the server's clock (1,000 seconds ahead of its own) sees a mirrored `Timer` and `Ticking` ring within 100 ms of the server's game time |
| `replication_bench` | 10,000 mirrored entities, 1% moving each tick, one bot: bytes and `Send` microseconds per tick (`--environment=server` and `--environment=bot`, `--optimized`) |
| `wire_probe` | an `Entity` naming a mirror goes on the wire as the remote id, and the other side reads its own id back; through a link component's codec, a mirror arrives as the receiver's own entity and a sender's own entity arrives as a new mirror |
| `timers_check` | timers ring on the right ticks and a one-shot is seen with its `Timer` on its ring tick; a paused timer (a `Timer` without `Ticking`) holds, then rings three ticks after it resumes; an `Expires` cooldown child is despawned and the link naming it goes; a list system's writes to inline components stick, a list system whose first list is empty never runs, and `run`'s fixed-rate pacing holds 25 ms ticks |
| `server_bench` | 5,000 players and 10,000 monsters moving on a 4 km square: spatial grid, aggro and area-of-interest queries, timers, and the profile; a grid query is checked against brute force. Run with `--optimized` |
| `physics_check` | every pair of collider shapes against sampling (overlap or not, decided by points well inside or well outside both); 300 raycasts, 300 sphere sweeps and 300 capsule sweeps through the grids against testing every collider, and 25 of each against marching the shape along its path; a character sliding along a wall, stepping up 0.25 m, stopped by a 0.6 m block and by a 60 degree slope, and walking up a 20 degree slope without leaving the ground; a character walking through a trigger, its entry and exit each seen once by a system before `TrackTriggers` and one after |
| `physics_bench` | 5,000 characters walking over a square kilometre among 10,000 turned boxes and 200 triggers: prints the tick time, the narrow tests per tick and every physics system above 50 µs; `--brute-force=true` tests every collider in every query instead of the grids. Run with `--optimized` |
| `navigation_check` | a cooked walkability grid: a 20 degree ramp is walkable at its height and a 60 degree one is not, ground under a 1.5 m ceiling is not and under a 2.5 m one is, a heightfield plateau is walkable and its 75 degree sides are not, and a wall mesh cuts the ground; A* costs equal a brute-force Dijkstra's on 40 random grids; line of sight is blocked by the wall and never squeezes between two diagonal blocked cells; a bot walks around the wall until it has `Arrived`, never leaving walkable cells, while a bot asking for an island gets `Unreachable` |
| `navigation_bench` | bakes a 2048 by 2048 cell grid from a terrain and 3,000 boxes, then measures A* queries per second on one thread and on the pool, and 10,000 bots asking at once through the systems; run `--optimized` |
| `texture_compression_check` | every compression setting on generated textures: the format, the 7 levels of a 64x64, a Pack round trip and a peak signal-to-noise floor per format; a checkerboard's last level is 188 when averaged in linear light and 128 when averaged as stored; `'user_interface'` leaves a texture alone. With `--source=a.psd;b.psd` (and `--compression=normal_map`, `--repeat`, `--single-thread`, `--dump=<prefix>`) it measures decode, mip and encode milliseconds, bytes and signal-to-noise on real files; run `--optimized` |
| `psd_zip_probe` | sixteen generated PSDs, layered and flat, 8 and 16 bit with raw, PackBits, ZIP and ZIP-with-prediction channels, decode to the expected checksum (`python make_fixtures.py` regenerates them) |
| `zstd_probe` | decompresses a `.blend` (`--source=file.blend --output=plain.blend`); compared byte for byte with Zig's decoder when it was written |
| `blend_probe` | a `.blend`'s datablocks, any SDNA struct, and a mesh's attributes (`--source=file.blend`) |
| `blend_mesh_check` | the mesh reader's triangles and corner normals match Blender's own loop triangles and corner normals for thirteen generated meshes (concave and collinear n-gons, custom, weighted and free normals, sharp edges, a scaled object); `--blend=file.blend --reference=file.json` checks another file against a reference dumped with `blender -b file.blend --python make_fixtures.py -- --reference=file.json`; Blender 5.2 runs `make_fixtures.py` to regenerate the fixtures |

## A test ends on a trigger, never a count

A test decides it is done from a condition that proves it, never from a frame count, a sleep or a timeout: those pass
on a quiet machine and fail on a busy one. `render_parity` shows why. Textures become ready in the `last` phase,
after that tick's `DrawUi`, so "textures are all ready" after a tick can still describe a draw list recorded without
them, two rectangles short whenever a load finishes one tick late. So it ticks until a tick *started* with every
texture resident and drew the same rectangles as the one before; with no fixed warm-up ticks, every run takes that
path.

## The click test is its own program

The game holds no test code. `examples/click_counter_test/` is a program that loads `../click_counter` (the whole
game, its systems and recipes included) and adds its own:

| System | Does |
|---|---|
| `TakeOverWindow` (`prepare`) | on `Added<Window.Component.Window>`: hides the window (unless `--show-window=true`) and adds `Component.Progress` |
| `DriveClicks` (`update`) | posts real `WM_LBUTTONDOWN`/`WM_LBUTTONUP` messages at the button, a few frames apart |
| `Verify` (`last`) | once every click is settled: checks the count, the label, the button's layout and its hover plate, prints, crashes on any difference, and quits |

So the test runs exactly the composition the game ships. It shares the game's cooked assets by declaring `base_folder()`
(see [assets-and-recipes.md](assets-and-recipes.md#worktrees-and-shared-cooking)). It prints
`clicks 5 label 5 texture ui.button.primary.hover button at 232 202 passed true`.

## Looking at a frame

The visible game can be driven from outside for screenshots: post `WM_MOUSEMOVE`, `WM_LBUTTONDOWN` and
`WM_LBUTTONUP` to its window, then capture its client area.

---

Next: back to [the documentation index](README.md), which lists every page in reading order.
