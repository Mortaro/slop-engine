# Testing



Every behaviour the docs claim is checked by a program in `examples/`. Run them from `examples/` with
`D:/Projects/SpiteLanguage/bin/spite`; each ends with its memory balance when given `--debug-memory`.

| Program | Proves |
|---|---|
| `click_counter_test` | the whole game through real Win32 messages in a hidden window: 5 (or `-- --clicks=N`) presses and releases posted to the window, counted by `CountClicks`, shown on the label, and the button left on its hover plate by the style systems |
| `text_field_test` | the text_field game in a hidden window: a click focuses the first field, real `WM_CHAR` and `WM_KEYDOWN` messages edit it to "HEXLL" with the caret at 3, then Tab moves focus to the second field, which receives "Y" |
| `scroll_list_test` | the scroll_list game through real Win32 messages in a hidden window: two wheel notches scroll the list by 80, the rows move with it, and a click lands on the row now under the pointer |
| `click_counter_online/test.sh` | a server and three headless bots in separate processes: the first bot joins at 0 and clicks 3 times, the second joins later and sees 3 without clicking, the third sees 3 and makes it 5. Run `bash examples/click_counter_online/test.sh` |
| `hot_reload_test` | a source file rewritten while the app runs is re-cooked on a worker, noticed by the engine's own watch on the cache, reloaded and re-uploaded: the software canvas and Vulkan follow red then blue, and it prints the worst tick meanwhile (2 ms) |
| `flex_layout` | 91 checks: flexbox boxes (justify, grow and shrink, alignment, reversal, order, relative and absolute positioning, box model, wrapping), grid tracks, a scrolled and clipped panel, and z-index paint order, each box to 0.01 pixel |
| `render_parity` | Vulkan and the software rasteriser draw the same frame, textured button, alpha edges and a wall of text of about 9,000 rectangles included: 0 of 256,000 pixels differ |
| `lights_check` | a red point light and a blue spot light on a dark floor through the clustered shader: the pixel under the point light is lit red and a far corner stays dark; `extra_lights` adds a grid of lights for timing |
| `tracking` | `Added<T>` and `Removed<T>` are each seen exactly once by a system before the change and one after it |
| `use_potion` | two related rows: each potion heals only the hero its `owner` points at, only if that hero is `Alive`, and a replaced component is written back |
| `healing` | headless systems, entity ids in rows, and two independent systems sharing a parallel stage |
| `stress` | 200,000 entities through two systems; prints the tick time |
| `asset_round_trip` | an asset class with every kind of field saved and read back through its derived codec |
| `psd_probe` | `buttons.psd`'s layer tree and sizes |
| `interest_check/test.sh` | area of interest across two processes: a bot's view of 100 beacons follows the server's eye (6, then 11), and a despawn in view reaches it (10) |
| `relations_check` | relations set, changed and removed at run time; a two-row system joins 10,000 items to their 1,000 parents |
| `wire_probe` | an `Entity` field naming a mirror goes on the wire as the remote id, for an inline and a reference component alike |
| `timers_check` | timers ring on the right ticks, a list system's writes to inline components stick, a list system whose first list is empty never runs, and `run`'s fixed-rate pacing holds 25 ms ticks |
| `server_bench` | 5,000 players and 10,000 monsters moving on a 4 km square: spatial grid, aggro and area-of-interest queries, timers, and the profile; a grid query is checked against brute force. Run with `--optimized` |
| `psd_zip_probe` | sixteen generated PSDs, layered and flat, 8 and 16 bit with raw, PackBits, ZIP and ZIP-with-prediction channels, decode to the expected checksum (`python make_fixtures.py` regenerates them) |
| `zstd_probe` | decompresses a `.blend` (`-- --source=file.blend --output=plain.blend`); compared byte for byte with Zig's decoder when it was written |
| `blend_probe` | a `.blend`'s datablocks, any SDNA struct, and a mesh's attributes (`-- --source=file.blend`) |

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
