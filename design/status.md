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
- `Changed<T>` (2026-10-02), known gaps:
  - a row counts as written per whole argument and per function, from `function.accesses`: a system that may write
    a row stamps every entity it visits, whether or not this run's branch wrote it. Bevy detects a write per
    mutable access at run time; here the answer is a row matching only what the system changes. Per-piece and
    per-path answers from the compiler would narrow it.
  - `Lookup<T>.of` always stamps, since it lends a writable item, so a system that only reads through a lookup
    marks what it reads as changed. Proposal: a read-only `Lookup<T>.read(entity)` once `accesses` can tell the
    two apart.
  - An IO system's rows are snapshots and are never written back, so their writes to reference components are not
    stamped.
  - A system writing `T` through a lookup made inside a function body, or through a column reached another way, is
    invisible to the runner and stamps nothing.
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
  - the watcher is interim (a standard-library file watcher that Spite's own hot reload would share is Mortaro's
    decision): `FindFirstChangeNotification` on Windows, `inotify` on Linux (2026-10-02, checked with a probe that
    writes a file into a watched folder; no example re-cooks on Linux yet).
- `examples/store_race_test` without the store lock: 5,965 of 8,000 records came back wrong or missing.
- Texture compression (built 2026-10-02, game alert A3), known gaps:
  - BC7 uses mode 6 only (one subset): about 3 dB over BC1 and BC3 on the tested textures, below what a
    multi-mode encoder (bc7enc, Compressonator) reaches. `'bc7'` is opt-in, as in Unreal;
  - the encoders are stb_dxt-style (principal axis, least-squares refinement); not yet compared with NVTT,
    which Unreal uses, on the same images;
  - box filter only: Unreal's Kaiser and Sharpen mip settings, alpha-coverage-preserving mips for masked materials,
    BC6H for HDR, BC4 for `TC_Alpha`, `TC_Displacementmap` and the per-texture LOD bias are not built;
  - textures are whole in VRAM: streaming mips by distance (Unreal's texture streaming) is not built, and a
    texture's lower mips do not arrive first;
  - colour formats are `UNORM` with the sRGB decode in the scene shader, so the GPU filters in sRGB space; `_SRGB`
    formats (filtering in linear light, as Unreal does) need the scene shader's decode to go (a proposal in
    design/decisions.md). Terrain colour arrays already use `_SRGB`;
  - `Psd.Layers.texture` cuts only uncompressed UI plates; a theme that wants compressed cuts calls `pixels_of` and
    the compressor itself.
- Texture compression measured 2026-10-02 (optimized, Ryzen 9 5950X, 31 pool workers):
  - 78 terrain layers (1024x1024 PSDs, `'default'`, all BC1): 436 MB as RGBA8 with mips, 54.5 MB cooked (8x);
    1.1 s to compress all (14 ms each); peak signal-to-noise 36.4 dB on average, 28.4 dB at worst (dense grass;
    BC7 gives 33.2 dB on it);
  - a 2048x2048 albedo with alpha (BC3): 34 ms (8 ms a megapixel), 40.0 dB, BC7 42.8 dB;
  - a 4096x4096 normal map: BC1 103 ms (6.1 ms a megapixel) at 46.6 dB, BC5 88 ms (5.2) at 61.0 dB on X and Y,
    BC7 199 ms (11.9) at 51.0 dB; single-threaded, BC1 encoding alone took 388 ms and BC7 1,584 ms;
  - the Kal archer's cook went from 838 to 860 ms with its textures compressed (zstd dominates it); `render_bench`'s
    textures hold 480,728 bytes against 3,145,725 as RGBA8 with mips (6.5x), and its GPU passes did not change
    (frame 530 to 520 us, scene 419 to 408 us, medians of three);
  - loading a cooked texture is one block copy: 3 ms for the splat map's 47 MB, where converting the
    `List<Integer>` took 92 ms.

## [loaders.md](../docs/loaders.md)

- PSD: decoding into byte planes and straight into the texels took the 3328x3584 splat map from 225 ms (683 ms on
  2026-09-26, with the compiler of the time) to 40 ms, a 2048x2048 albedo from 104 to 30 ms and a 4096x4096 ZIP
  normal map from 332 to 91 ms (2026-10-02, optimized). The per-pixel interleave is single-threaded. PSB is not read.
- `.blend`, not built yet: more than one UV set and vertex colours (both need `Asset.Mesh` and the scene shader to
  carry more per-vertex data), and cooking images that reference external files (the reader reports their paths).
- `.blend` corner normals differ from Blender's in one case: a fan whose normal space Blender cannot build (an edge
  almost along the fan normal, on degenerate geometry) keeps the fan normal, where Blender answers a zero normal.
- `blend_mesh_check` against Blender 5.2 (2026-10-02): the thirteen fixtures match its loop triangles exactly and
  its corner normals to 7e-6; the archer's 21 meshes (all triangles, encoded custom normals) to 9e-4, the worst on a
  folded, non-manifold pocket of tiny triangles in `Body - Chest`, and 1e-6 elsewhere.

## [scene.md](../docs/scene.md)

- Normal, roughness and metallic maps are not read yet.
- Levels of detail and occlusion culling (2026-10-02), known gaps:
  - every level shares the mesh's full vertex buffer (a level is only indices), so levels cut triangles and vertex
    shading but not vertex memory;
  - UV stretching is not costed by the simplifier (seams are kept, interior UVs follow the collapsed vertex);
  - the shadow pass draws each model at the view's level (no coarser shadow level), and models outside the view
    cone still cast no shadow;
  - one `DetailLevel` per model, so two views of one model share its hysteresis;
  - no dithered transitions between levels (Unreal's are off by default for static meshes);
  - occlusion tests models only, not terrain cells; a model uncovered by a moving eye or occluder shows one frame
    late (two when the GPU is a frame behind); the occlusion map is copied into a `List<Float>` each frame (8,160
    floats at 1080p);
  - `render_bench` (optimized, RTX 3090, 1920x1080, medians of 3): the default scene went from frame 569, shadows 79,
    scene 453 us to frame 579, shadows 76, scene 432, occlusion depth 25 us, with an identical capture; with
    `--field=60` (3,600 flowers of 44,800 triangles behind a wall) the frame takes 27.6 ms with neither, 0.96 ms
    with levels of detail, 16.3 ms with occlusion culling and 0.93 ms with both (4,619 of 7,144 draws hidden, 0.45
    million scene triangles instead of 145 million). Gathering the 3,600 flowers costs about 0.4 ms more CPU with
    occlusion on. The flower cooks into 8 levels in 2.3 s.
- Dithered fades (Unreal's OccluderDither at a non-zero fade) are not built yet.
- A light that is a child of a moving entity reads only its own position (proposal: follow the parent once
  transforms have a world pass).
- Point and spot lights, not built yet:
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
- Grass (built 2026-10-02 for a game's alert A57), not built yet:
  - grass casting shadows (Unreal's `bCastDynamicShadow`; the game's types all have it off);
  - the density map is the only weight: no terrain layer weight drives a type, nor the game's slope gate and slope
    noise from its grass material (it exports those as a material, `grass.json`), nor its far-density thinning;
  - per-distance mesh LODs (the game's grass meshes have three), which the LOD work would bring;
  - the ground capture sees only the terrain cells in view, so grass on a cell just outside the view cone is not placed
    even when its blades would reach into view;
  - the instance buffer holds a slot for every grid point of every type's square (`(2 · end / spacing)²`, 32 bytes
    each): the game's tiny grass (12 per m² to 90 m) takes 12 MB.
- Grass cost (foliage_check, optimized, 1920x1080, RTX 3090, 2026-10-02): scatter 52 µs, draw 714 µs at 8 + 1.5
  instances per m²; at three times the density 62 µs and 1.82 ms. The draw scales with pixels (212 µs at 960x540),
  so it is shading; a depth prepass made it slower (957 µs).
- Water (built 2026-10-02 for alert A57), not built yet: reflections of the scene (only the sky is reflected; Unreal
  uses screen-space reflections), spline-shaped bodies (a body is a rectangle and the terrain's depth draws the
  shore), seeing from under the surface, foam, caustics, rivers and flow maps, waves masked near the shore (Unreal's
  "Water Depth to Mask Waves"), and reading the wave height on the CPU for floating objects.
- `foliage_check`'s frame shows about twenty single black pixels along the terrain's silhouette at the basin's rim,
  with or without the water and away from the grass; cause not found yet.
- Shadows, not built yet:
  - contact shadows, and soft shadows that harden toward their caster (PCSS);
  - a model that casts no shadow (Unreal's per-primitive Cast Shadow), and per-light bias settings (Unreal's Shadow
    Bias and Shadow Slope Bias);
  - sizing a light's tiles by its screen size, as Unreal does: every tile is 512²;
  - caching static casters apart from movable ones: a light with a skinned model in reach redraws all its faces
    every frame, within the face budget;
  - terrain cells outside the view cast no shadow;
  - more than one view a frame: each view replans the atlas, and the cached light tiles serve only the last one;
  - the atlas is a fixed 8192×4096 at 32 bits (128 MB), whatever the settings use.
- Shadow cost in `render_bench` (optimized, 1920x1080, RTX 3090, median of 3, 2026-10-02): before, shadows covered only
  6 m around the camera's target, frame 541 us, shadows 76 us, scene 429 us; with three cascades to
  200 m, frame 723 us, shadows 148 us (the sun's cascades), scene 539 us (the 5x5 filter on every lit fragment).
  `--shadowed-lights=8` adds local shadows 82 us (36 faces a frame) and scene to 615 us. A 7x7 filter cost 20 to
  30 us more in the scene pass.
- Not built yet, from the previous Kal renderer: the ray-marched atmosphere and sky; contact shadows; image-based
  sky lighting; 4× MSAA.
- Post-processing, not built yet or not checked against Unreal:
  - a velocity buffer: temporal anti-aliasing reprojects the camera's motion only, so a walking character leans on
    the colour clip and can smear a little;
  - a texture mip bias while upsampling (Unreal biases by the log2 of the screen fraction), so a screen percentage
    below 100 also blurs textures by up to a level;
  - Unreal's filmic path also has blue correction (0.6) and a gamut expansion (1.0) around the curve, and colour
    grading, white balance, local exposure, lens flares, a bloom dirt mask, film grain and chromatic aberration:
    none are built;
  - the bloom Gaussian's sigma (half the radius), its reach (three sigma) and the tint scale (one sixth) follow
    Unreal's code as remembered, and the vignette's circle (corners at distance 1) likewise: compare against a
    capture of the game in Unreal;
  - auto exposure weighs every pixel alike (no metering mask or centre weighting), over a fixed EV100 range of -10
    to 20;
  - image-based sky lighting: the sky and ground hemisphere is already the exact irradiance of the engine's
    two-colour sky, so spherical harmonics or a prefiltered cubemap pay off only once there is a sky model (the
    atmosphere); the sky's specular reflection is a flat 0.25 of the ambient;
  - one post-processing state per renderer: several windows would share the history and the exposure;
  - removing a settings component leaves its last values in the views instead of Unreal's defaults.
- `render_bench` (optimized, 1920x1080, RTX 3090, median of three), 2026-10-02: before post-processing, frame 525 µs
  (shadows 77, scene 412, ACES tone map 17); after, see [performance.md](../docs/performance.md#measuring-the-gpu).
- Animation (2026-10-02, Claude; built headless and checked by `animation_check` on Linux):
  - **To look at on Windows** (needs the Kal assets and a GPU): `kal_character` and `animate_bench` now load
    `slop_scene_animation_plugin`, which shares the pose with the `Skin` and maps `OffView` to `Unseen`; check that
    the archer is skinned and animates as before (the joining plugin was run on Linux only against copies of the
    scene's `Model`, `Skin`, `OffView` and `Pose`: the `Skin` shares the pose's lists, an `OffView` model holds its
    pose and moves again once seen), that models leaving and re-entering the view still pose, and that
    `animate_bench`'s Animate time is no worse than 9 ms. The loop now wraps at the last key instead of
    interpolating from the last key back to the first over one more frame: the idle, walk and run loops should
    have no hitch at the wrap; if an action does not end on its first pose, it now pops there instead of easing,
    and the recipe should key its last frame equal to its first. Blending, crossfades and throttling have not been
    seen on screen: a crossfade from idle to run in `kal_character`, and `animate_bench` with throttles, are worth a
    look.
  - **Question, loop start: on the animator or on the clip?** Built: `loop_start` is a field next to every clip name
    (`Animator`, `Crossfade`, `Layer`), so a game sets it where it names the clip. Options: (a) keep it there; (b) a
    field of `Asset.Animation`, cooked from a pose marker in the Blender action (for example one named `loop`), so
    the clip carries its own loop wherever it plays; (c) both, the animator's overriding. Recommendation: (b), since
    the loop is a property of the authored clip; it changes the asset format in `slop/` (a re-cook) and the action
    reader.
  - **Question, where the skin and the visibility marker live.** The scene plugin keeps `Scene.Component.Skin`,
    `Scene.Pose` and `Scene.Component.OffView`, and `slop_scene_animation_plugin` joins them to the headless
    animation plugin (the `Skin` shares the `Pose`'s lists; `OffView` adds `Unseen`, one tick later, as before).
    Options: (a) keep the joining plugin; (b) move the skin pose and one visibility marker into `slop/`, which both
    plugins then read, and drop the joining plugin and its tick of delay. Recommendation: (b) if more plugins come
    to need visibility (particles, sound), else (a).
  - Throttle phase: a game sets `Throttle.phase` per character (all parts the same) to spread far characters over
    the ticks; left at 0, every far animator samples on the same ticks. A default derived from the entity (the
    `Parent` of a character's parts, when they have one) is a possible next step.
  - `ThrottleByDistance` costs throttled animators times viewpoints each tick; a server with many observers should
    find the nearest one through the spatial grid (not built).
  - Not built: bone masks (a layer that moves only some bones), additive layers, sync groups (a walk and a run
    blended at the same phase), and root motion.
  - `animation_bench` (optimized, Linux, 4 cores shared with four other builds, medians of 5 interleaved runs,
    2,800 animators, 400 distinct samples a tick, 65 bones): the Animate system as it was, 45.4 ms a tick (62
    animators per millisecond); the new one unthrottled, 42.0 ms (67 per millisecond); throttled in rings 4 to 94 m
    from the camera, 19.7 ms (142 per millisecond). "As it was" ran the previous plugin against stand-ins for the
    scene's `Model`, `Skin`, `OffView` and `Pose`.

## [physics.md](../docs/physics.md)

Built 2026-10-02: box, sphere, capsule and static mesh colliders, the grid broad phase, raycasts and sphere and
capsule sweeps, the character controller and triggers. Not built yet:

- **Rigid-body dynamics**: mass, forces, impulses, friction, restitution, stacking, sleeping, joints. Nothing in
  the engine simulates bodies; colliders are static or moved by code, and characters by their controller.
- **Contacts between solid colliders** as entities (only trigger overlaps are), which dynamics would need.
- **A heightfield collider** (the roadmap's terrain collider). A terrain can be a `MeshCollider` today, at one
  broad-phase entry per triangle.
- **Collision layers or filters**: every query hits every solid collider, and every trigger sees every character
  and kinematic collider.
- **Box sweeps and public overlap queries** (`overlap_sphere`, `overlap_box`): the overlap test exists, used by
  triggers and the controller, but has no query function yet.
- **Mesh colliders from a recipe**: a `.blend`'s `UCX_` collision objects cooked into `Physics.Meshes` (roadmap
  item 9). Meshes are built in code today.
- **Kinematic mesh colliders**: a mesh is placed once; moving one means adding its component again, which re-reads
  every triangle.
- **Per-mesh acceleration shared between instances**: each placed mesh copies its triangles into the broad phase in
  world space, so a thousand copies of one rock cost a thousand times its triangles.
- **Scale on primitives**: a primitive ignores the transform's scale.

Known gaps:

- `MoveCharacters` is one system, so 5,000 characters run on one thread (no parallel iteration inside a system,
  above). It shares its stage with every system that touches neither `Transform`, the character components nor
  `Physics.Colliders`.
- Every system that binds `Physics.Colliders` counts as writing it (INSIGHTS bug 52), so systems that only query
  never run beside each other.
- Positions are `Float`s and contact is within 1 mm, which holds within a few kilometres of the origin; a larger
  world needs origin shifting or `Double` positions.
- The controller cannot push a character out of a box whose interior holds the capsule's whole core segment (spawned
  deep inside); it pushes out of anything shallower.
- Queries in a tick see kinematic colliders where they stood at the start of the tick.
- `Kinematic` and `Trigger` are read when the shape is added; adding or removing them later changes nothing until
  the shape is added again.

Questions for Mortaro:

- **Should characters collide with each other?** Options: (a) never: they pass through (today; most MMOs do this,
  and it is the cheapest); (b) a marker such as `Physics.Component.Solid` on a character makes it solid to the
  others' controllers, at one more broad-phase grid read per sweep; (c) always. Recommendation: (a), with (b) when a
  game needs body blocking.
- **Rigid bodies, and how far.** Options: (a) none, kinematic only (today); (b) simple bodies (sphere and box,
  gravity, bounce, no stacking) for loot and projectiles; (c) a full solver with stacking and joints. Recommendation:
  (b) first, as components (`Body`, `Velocity`, `Mass`) and systems, if a game asks.
- **Collision layers**: a layer component holding a bit mask (one component per collider), or a marker per layer
  (`Physics.Component.LayerProjectile`), filtered in queries. Recommendation: one `Layers` component with a mask and
  a query argument, since queries need to combine layers.

Measured (Linux, a 4-core cloud machine shared with four other builds, `--optimized`, three interleaved runs,
medians), `physics_bench`, 5,000 characters, 10,000 boxes, 200 triggers:

| Broad phase | Tick | `MoveCharacters` |
|---|---|---|
| none: every query tests every collider (`--brute-force=true`), the "before" | 5,128 ms | 4,832 ms |
| the grids | 14.1 ms | 10.9 ms |

History of the grid run: 24 ms a tick at first; 15 ms once a segment beyond a box face tests that face's 4 edges
instead of all 12, and `lesser`/`greater` replaced `Float.minimum`/`maximum` (INSIGHTS, 2026-10-02); 13.5 to 14 ms
once characters left the grids that solid queries read.

## [networking.md](../docs/networking.md)

The whole page is Claude's proposal, unconfirmed; Mortaro decides the API. It is built and tested by
`examples/click_counter_online`, `interest_check`, `replication_check`, `handshake_check`, `unreliable_check` and
`clock_check`. Not built yet, in rough order of need:

- **Values inline in columns** for the codec: copying a component's bytes instead of walking its fields.
- **Prediction and rates**: client-side prediction and reconciliation of what a client owns, and a send rate per
  connection or per component.
- **Send still walks every mirrored row and every known entity per peer each tick** (a stamp check and an empty
  queue each), so 10,000 quiet entities still cost about 1.4 ms a tick. A per-column log of written entities and a
  per-peer list of entities with changes would make it follow only what changed.
- **Datagram security**: a datagram is matched to its connection by a token sent in the clear in the hello; the
  acceptor takes the dialer's address from the first datagram with the token and never changes it. Anyone who reads
  the TCP stream can forge datagrams. Authenticating them waits on encrypted connections (Spite's TLS, D394).
- **Datagram reordering** is handled by dropping anything older than the newest tick seen; there is no test that
  reorders real packets (localhost does not), only a forged stale one.
- **IO through Spite's concurrent-by-default IO (D378)** is not built in Spite master (2026-10-02): `Socket`'s
  blocking calls park inside a `Concurrent` only for `accept_client`, `read_line` and `read_bytes`, `connect` still
  blocks its thread, and `UdpSocket` has no parking calls at all. The plugin keeps polling non-blocking sockets once
  per tick and dialling on the thread pool, which never blocks a frame; it can move to plain straight-line IO once
  D378 lands.
- **Messages before the handshake**: a message spawned while no peer is greeted is despawned unsent, as one spawned
  with no connection always was.
- Measured on Linux (shared 4-core machine, `--optimized`, `replication_bench`: 10,000 mirrored entities, 100 moving
  each tick, one bot, 300 measured ticks, five interleaved runs each, medians, 2026-10-02):

  | | Before (encode and compare every value) | After (encode what was written) |
  |---|---|---|
  | `Send` per tick | 7,889 µs | 1,403 µs |
  | Bytes per tick | 2,000 | 2,000 |
  | Tick with 16 ms pacing | 24,465 µs | 17,938 µs |

## [navigation.md](../docs/navigation.md)

Built 2026-10-02 (the roadmap's item 6); the API is Claude's proposal ([decisions.md](decisions.md#navigationmd)).

- Not built yet:
  - the roadmap's later inputs: water and safe planes, and reading collision (`UCX_` meshes, collection instances)
    from a map's `.blend`; a recipe passes triangles to `Navigation.Bake` by hand today;
  - an agent radius: cells are not eroded, so a path may run along the cell next to a wall;
  - several floors per cell: the grid keeps the highest floor with room, so the ground under a bridge is lost;
  - runtime changes to the grid (doors, dynamic obstacles) and avoidance between bots;
  - a smooth height: a walking bot takes its cell's height, which steps on slopes.
- Known gaps:
  - Replacing a `Destination` in place does not search again: `Added` sees only a new component, and there is no
    `Changed<T>`. A game removes and adds it in the same tick.
  - `RequestPaths` is a list system driven by `Added<Destination>`, and building that list walks every
    `Destination` each tick: about 0.7 ms a tick with 10,000 bots holding one (`navigation_bench`), whether or not
    one is new. An engine-wide cost of `Added` in list systems.
  - 10,000 destinations added in one tick cost about 21 ms in that tick's `RequestPaths` (making the batches and
    10,000 marker commands); answers land at most 512 bots a tick.
  - On Linux, `cookbook.cook()` ends by starting `Recipes.Watcher`, which is Windows-only, so headless programs
    (`navigation_check`) call `cookbook.cook_recipes()`; the docs present that as the server's way.
  - A `Navigation.Search` keeps 12 bytes per cell for each thread that searches: 48 MB at 2048 by 2048.
  - Search speed is bound by `List` reads and writes, which stay calls in the C (`List_Long_set_at`,
    `List_Integer_set_at`, the binary heap's sifting take most of a query in callgrind): about 0.5 µs per expanded
    cell. Inlined list access (D402's work) is the expected win.
- Question for Mortaro: one grid per program (`Navigation.Map`), or one per space as `Spatial.Grid` has, so
  instances and dungeons sharing coordinates each have their own? Options: (a) keep one grid (simplest, a server
  per map); (b) a `Dictionary` of grids keyed by `Spatial.Component.Indexed.space`, read by the systems from each
  bot's `Indexed`; (c) a grid entity per map and a link on each bot. Recommendation: (b), matching the spatial
  grid, once a game runs several maps in one process.
- Measured (2026-10-02, Linux, 4-core cloud machine shared with four other builds, `--optimized`, medians of 3
  runs of `navigation_bench`): baking 2048 by 2048 cells from a 512 by 512 quad terrain and 3,000 boxes (560,288
  triangles) takes 5.3 s; A* with smoothing on that grid answers 2,670 queries per second on one thread for goals
  within 125 cells (622 cells expanded on average, unreachable goals answered at once) and 140 per second for goals
  within 600 cells; four threads answer 3,730 per second (the machine was loaded, so this is to measure again on
  Windows); 10,000 bots asking at once through the systems are all answered within 3.0 s, worst tick 46 ms.

## [performance.md](../docs/performance.md)

GPU timings (`renderer.gpu_timings`) are Claude's proposal, unconfirmed. They are not yet in `app.profile()`, and
passes of several windows add into one average per name.

There is no parallel iteration inside one system. Rows a system only
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
| Texture decode format | fixed (2026-10-02): textures are stored GPU-ready, block-compressed with their mips when a recipe compresses them, and a load copies one block |
| Spawning a streamed region | open: needs spawning spread over frames. `create_entity_from_bundle` computes each component's column key as a string, so bulk spawning got 2x slower with the entity API (200,000 bodies: 520 ms to 950 ms), and short strings brought it back to 510 ms; integer ids per component class instead of string keys are the next step |
| Layout | open: the whole UI tree is laid out every frame. Fine for menus; an in-world UI needs dirty-subtree layout |
| Streaming a row | improved: a single-row `_each` system cost about 300 ns per entity even when its body only copied eight floats (`GatherPointLights`, 3,000 rows: 0.9 to 1.1 ms). Most of it was singleton locks: with Spite's reader-side locks, the lock skipped when no `Parallel` runs (d13aae7), and inline storage inferred, it is 0.33 ms, about 110 ns per row (optimized, 2026-09-28). The same change took `server_bench` from 7.7 to 7.4 ms. `stream_bench` (100,000 rows, optimized): one inline component 22 ns, two 37 ns, `Entity` plus one 31 ns, and an inline plus a reference component 180 ns, of which `Column.at` checking and then reading the item cost 35 (now one read, 143 ns). The rest is Spite's generated C: every reference fetched is retained and released (two atomic writes on a cold object, about 70 ns), every inline attribute retains its column's `Items` and takes the singleton guard (about 15 ns), and the row `Vector` is retained per row. Reported to Spite (2026-09-28) |

## [testing.md](../docs/testing.md)

- On Linux (2026-10-02, Spite master): the headless core and its examples build and run, balanced under
  `--debug-memory`; the store lock goes through `flock` there (`os/linux/`). Still Windows-only: the window, input
  and XInput plugins, the software presenter (GDI) and Vulkan's `vulkan-1.dll`; those examples were compiled for
  Windows in check mode only. The UI plugin loads `spite_truetype`, which must sit beside the engine.
- On Windows (2026-10-02, Spite master `2d84122`, every engine branch integrated: runner gaps, physics, navigation,
  networking, animation, render foundation, `.blend` meshes, foliage, textures, shadows, post-processing, levels of
  detail; the MongoDB driver pinned at `df985e6`): every program in testing.md passes balanced under
  `--debug-memory` (benches `--optimized`), with `render_parity` at 0 of 256,000 pixels and `flex_layout` 92 of 92,
  plus `io_systems`, `mongodb_check`, `scene_probe`, `kal_character --frames=300`, `waits_check` and
  `template_wait_check`. `replication_bench` runs as `--environment=server` and `--environment=bot` (2,000 bytes and
  695 us of `Send` a tick).
  Two examples building at once can collide checking out the same pinned package (`<package>.index.lock` exists);
  the second build fails and passes when run again.
- On Spite master `8e971f26` (2026-10-02), after moving to the standard library's maths and renaming the classes
  D374 refuses (the MongoDB driver pinned at `fd2aa14`): every program in testing.md passes balanced under
  `--debug-memory` (benches `--optimized`), `render_parity` at 0 of 256,000 pixels, with the extras above.
  Medians of three against Spite `2d84122` and the engine before the move, run back to back on a loaded machine
  (optimized, RTX 3090): `render_bench` frame 1,665 against 1,674 us, `animate_bench` frame 23.8 against 23.5 ms,
  `props_bench` frame 15.6 against 14.2 ms, `stress` tick 10.9 against 12.0 ms. Built with Spite `2d84122`, the
  moved engine matches the old one (`props_bench` `GatherModels` 8.5 against 8.7 ms); the rest of `props_bench`'s
  gap, `GatherModels` about 1.3 ms slower, came with Spite's seed `bad39937` and is reported to the language.
- `render_bench` with everything on (2026-10-02, optimized, RTX 3090, `--shadowed-lights=8`, levels of detail,
  occlusion culling and BC textures): frame 1,428 us at 100% and 982 us at `--screen-percentage=67`; the per-pass
  table is in performance.md. Before the animation plugin's pose moved out of the scene, `render_bench` did not load
  `slop_scene_animation_plugin`, so its archers drew unskinned and the cached light tiles never redrew (local shadows
  0 us).

- The tests that still capture at a frame number (`scene_probe`, `lights_check`, `terrain_check`,
  `kal_character`'s `--frames`) are to move to a trigger, as `render_parity` did. `render_parity` used to capture two
  rectangles short whenever a load finished one tick late.
