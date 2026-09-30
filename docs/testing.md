# Testing



Every behaviour the docs claim is checked by a program in `examples/`. Run them from `examples/` with
`D:/Projects/SpiteLanguage/bin/spite`; each ends with its memory balance when given `--debug-memory`.

Measure performance only with a production build (`--optimized`, no `--repl`, no `--repl-port`, no `--hot-reload`,
no `--debug-memory`). REPL and hot-reload builds are slower on purpose: they exist to show more while the program
runs (functions in swappable slots, breakpoints, live inspection), not to be fast, so a number measured on one
describes the tooling, not the engine.

| Program | Proves |
|---|---|
| `click_counter_test` | the whole game through real Win32 messages in a hidden window: 5 (or `-- --clicks=N`) presses and releases posted to the window, counted by `CountClicks`, shown on the label, and the button left on its hover plate by the style systems |
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
| `attachment_check` | a bone attachment follows a named bone with an offset, and another follows a bone index, on a synthetic skeleton turned a quarter: both land where the maths says and carry the turn |
| `inline_string_probe` | inline components holding long text and an enum: `_each`, `_all` and two-row systems, bundle spawns and writes through `Lookup.of` stay balanced under `--debug-memory` |
| `stream_bench` | nanoseconds per row of single-row systems by shape (one inline component, two, `Entity` plus one, inline plus reference) over 100,000 entities; run `--optimized`, and `-- --parallel=false` for sequential stages |
| `snapshot_write_refused/test.sh` | an IO system that writes an inline component of its row fails to compile, and the error names the writing line |
| `terrain_check` | a cooked two-by-two-tile terrain: each tile's base layer and a painted splat circle land where the ported M_Terrain formula puts them |
| `props_bench` | 17,000 cube props in a grid: prints the frame time and every system above 0.2 ms; run `--optimized` |
| `animate_bench` | 400 seven-part Kal archers (2,800 animators) in rings around the camera, each archer at its own time: prints the frame time and every system above 0.1 ms; run `--optimized` |
| `resize_check` | a hidden window resized, minimised and restored: the swapchain is rebuilt to the new client size, minimised frames are skipped, and presenting resumes at full size |
| `without_check` | a system over `Health` and `Without<Frozen>` heals only entities without `Frozen`, and heals one once its `Frozen` is removed |
| `tracking` | `Added<T>` and `Removed<T>` are each seen exactly once by a system before the change and one after it |
| `use_potion` | two linked rows: each potion heals only the hero its `Owner` names, only if that hero is `Alive`, and a replaced component is written back |
| `healing` | headless systems, entity ids in rows, and two independent systems sharing a parallel stage |
| `stress` | 200,000 entities through two systems; prints the tick time |
| `asset_round_trip` | an asset class with every kind of field saved and read back through its derived codec |
| `psd_probe` | `buttons.psd`'s layer tree and sizes |
| `interest_check/test.sh` | area of interest across two processes: a bot's view of 100 beacons follows the server's eye (6, then 11), a despawn in view reaches it (10), links travel both ways (`Near` from the server, a message of a `Point` and its `Target` from the bot), and despawning the beacon the stashes are `Near` removes each `Near` on the bot too (9); a `Target` message naming the beacon the server despawned is dropped, and the server judges the valid one after it |
| `relations_check` | `Parent` links set, changed and removed at run time; a two-row system follows 10,000 items' `Parent` to their 1,000 players; a despawn cascades to children; despawning a hunter's prey removes its `Target` in that flush, and a `Removed<Component.Target>` row sees it |
| `list_component_refused/test.sh` | a component holding a `List`, a `Dictionary` or a `Parallel` fails to compile, each error naming the rule and the component |
| `dead_link_refused/test.sh` | adding a link component whose entity is despawned, or left at `Entity()`, crashes naming the rule |
| `wire_probe` | an `Entity` naming a mirror goes on the wire as the remote id, and the other side reads its own id back; through a link component's codec, a mirror arrives as the receiver's own entity and a sender's own entity arrives as a new mirror |
| `timers_check` | timers ring on the right ticks and a one-shot is seen with its `Timer` on its ring tick; a paused timer (a `Timer` without `Ticking`) holds, then rings three ticks after it resumes; an `Expires` cooldown child is despawned and the link naming it goes; a list system's writes to inline components stick, a list system whose first list is empty never runs, and `run`'s fixed-rate pacing holds 25 ms ticks |
| `server_bench` | 5,000 players and 10,000 monsters moving on a 4 km square: spatial grid, aggro and area-of-interest queries, timers, and the profile; a grid query is checked against brute force. Run with `--optimized` |
| `psd_zip_probe` | sixteen generated PSDs, layered and flat, 8 and 16 bit with raw, PackBits, ZIP and ZIP-with-prediction channels, decode to the expected checksum (`python make_fixtures.py` regenerates them) |
| `zstd_probe` | decompresses a `.blend` (`-- --source=file.blend --output=plain.blend`); compared byte for byte with Zig's decoder when it was written |
| `blend_probe` | a `.blend`'s datablocks, any SDNA struct, and a mesh's attributes (`-- --source=file.blend`) |

## A test ends on a trigger, never a count

A test decides it is done from a condition that proves it, never from a frame count, a sleep or a timeout: those pass
on a quiet machine and fail on a busy one. `render_parity` shows why. Textures become ready in the `last` phase,
after that tick's `DrawUi`, so "textures are all ready" after a tick can still describe a draw list recorded without
them. It captured two rectangles short whenever a load finished one tick late. It now ticks until a tick *started*
with every texture resident and drew the same rectangles as the one before; with no fixed warm-up ticks, every run
takes that path. The tests that still capture at a frame number (`scene_probe`, `lights_check`, `terrain_check`,
`kal_character`'s `--frames`) are to move to the same kind of trigger.

## The click test is its own program

The game holds no test code. `examples/click_counter_test/` is a program that loads `../click_counter` (the whole
game, its systems and recipes included) and adds its own:

| System | Does |
|---|---|
| `TakeOverWindow` (`prepare`) | on `Added<Window.Component.Window>`: hides the window (unless `--show_window=true`) and adds `Component.Progress` |
| `DriveClicks` (`update`) | posts real `WM_LBUTTONDOWN`/`WM_LBUTTONUP` messages at the button, a few frames apart |
| `Verify` (`last`) | once every click is settled: checks the count, the label, the button's layout and its hover plate, prints, crashes on any difference, and quits |

So the test runs exactly the composition the game ships. It shares the game's cooked assets by declaring `base_folder()`
(see [assets-and-recipes.md](assets-and-recipes.md#worktrees-and-shared-cooking)). It prints
`clicks 5 label 5 texture ui.button.primary.hover button at 232 202 passed true`.

## Looking at a frame

The visible game can be driven from outside for screenshots: post `WM_MOUSEMOVE`, `WM_LBUTTONDOWN` and
`WM_LBUTTONUP` to its window, then capture its client area.
