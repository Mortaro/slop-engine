# Assets and recipes

A game never reads an artist's file at run time. A recipe turns source files into assets, by id, into a cache; the
game names ids.

## Assets are declared classes

An asset format is a class. `Pack<T>` derives its binary codec from the class's attributes with a plural template,
and `Field<T>` decides each attribute's encoding at compile time: `Integer`, `Long`, `Float`, `Double`, `Byte`, `Boolean`,
`String`, `Asset.Bytes` (its length, then the bytes as one block), lists of any of these or of classes, and nested
classes. No format has a hand-written reader or writer.

```gdscript
# slop/asset/texture.spite
var width = 0
var height = 0
var format = "rgba8"
var levels = 1
var texels = Asset.Bytes()
```

```gdscript
var pack = Pack<Asset.Texture>()
var bytes = Asset.Bytes()
pack.encode(texture, bytes)
var decoded = pack.decode(bytes)
```

A file starts with `SLOP` and the class's name, so a file is never read as the wrong format. A project declares its
own formats the same way. `examples/asset_round_trip` checks one with every kind of field.

## Recipes are code

A recipe is a class in a `recipe/` folder with a `build()`. `cookbook.cook()` (`var cookbook = Recipes.Cookbook()`) finds every one and runs it when the
program starts, so nobody has to remember a separate step.

```gdscript
# examples/click_counter_theme_plugin/theme/recipe/ui.spite
var layers = Psd.Layers()

func build() {
    layers.open_in("../click_counter_theme_plugin/theme", "ui.buttons")
    layers.texture("Plates/Primary/Normal", "ui.button.primary.normal")
    layers.texture("Plates/Primary/Hover", "ui.button.primary.hover")
    layers.texture("Plates/Primary/Pressed", "ui.button.primary.pressed")
    layers.skip("Plates/Secondary/", "click_counter has one button, and it is primary")
    layers.skip("Close/", "click_counter has no window to close")
    layers.finish()
}
```

The steps:

| Step | Does |
|---|---|
| `Psd.Layers` | `open(id)`, `texture(layer path, id)`, `skip(prefix, reason)`, `finish()`, which refuses any layer nothing claimed |
| `Recipes.Glsl` | `compile(root, id, stage)`: GLSL to SPIR-V with `glslangValidator`; the plugin names its own folder as the root |
| `TextureCompression.Compressor` | `compress(texture, setting)`: a mip chain and block compression, below |

Any package can bring recipes along with its systems: the Vulkan plugin brings its shaders, a game brings its PSDs.

## Textures are cooked GPU-ready

An `Asset.Texture` holds exactly what the GPU reads: `format`, `levels` (the mip count) and `texels`, every level's
bytes from the largest down, each level's rows of blocks top to bottom. A loader answers an uncompressed texture
(`format` `"rgba8"`, one level, four bytes a pixel in R, G, B, A order); `pixel(index)`, `set_pixel(index, value)`,
`append_pixel(value)`, `pixel_count()` and `clear_pixels(width, height)` read and write one as packed
`0xAABBGGRR` integers, and `level_offset(level)`, `level_bytes(level)` and `expected_bytes()` find the levels of any
format.

A recipe compresses with `slop_texture_compression_plugin`, choosing a setting the way Unreal's Compression Settings
do:

```gdscript
var compressor = TextureCompression.Compressor()
var texture = document.pixels_of(layer)
var compressed = compressor.compress(texture, 'default')
pack.encode(compressed, bytes)
```

| Setting | Unreal | Format | Mips |
|---|---|---|---|
| `'default'` | `TC_Default` | BC1, or BC3 when any pixel's alpha is below 255 | averaged in linear light (sRGB colour) |
| `'masks'` | `TC_Masks` | BC1 or BC3, the same way | averaged as stored (linear data) |
| `'normal_map'` | `TC_Normalmap` | BC5: X and Y; the shader derives Z | averaged as vectors and renormalised |
| `'grayscale'` | `TC_Grayscale` | R8, uncompressed; sampled as (r, r, r, 1) | averaged in linear light |
| `'bc7'` | `TC_BC7` | BC7 (mode 6) | averaged in linear light |
| `'user_interface'` | `TC_UserInterface2D` | RGBA8, unchanged, one level | none: the UI samples it pixel-exact |

A BC4 texture is sampled as (r, r, r, 1) too. The mip chain is a 2x2 box filter (Unreal's SimpleAverage) down to 1x1;
each level of a large texture is split into bands of rows, and every band is filtered and encoded as a `Parallel` job
on the thread pool. The encoders fit each 4x4 block's endpoints along its colours' principal axis and refine them
by least squares; a block of one colour gets the endpoint pair that reproduces it best. `TextureCompression.Decoder`
decodes every format back to RGBA8 and measures `peak_signal_to_noise`, which `texture_compression_check` uses.

A texture stays uncompressed when nothing compresses it: `Psd.Layers.texture` cuts UI plates, so it keeps them RGBA8,
and the renderer makes their mips on the GPU. An `Asset.TextureArray` is layers of one shape and format:
`append_layer(texture)` adds a cooked texture's bytes, so a terrain array is its layers compressed one by one.

## Everything is named by id

An asset is named by its id everywhere, and a source file's path follows from the id: `ui.buttons` is
`assets/ui/buttons.psd`, `shader.rectangles.vertex` is `assets/shader/rectangles/vertex.glsl` (dots are folders,
the step supplies the extension). A recipe never writes a path, so no path can point outside the project, and the
lookup can be redirected, which is what worktrees need. `Recipes.Sources` does it: `path_of(id, extension)` looks in
the program's folder, then its base (below); `path_in(root, id, extension)` looks in one package's folder.

## The cache binary

Cooked assets live in one file, `<base>/.slop-cache/store.bin`, never as loose files. It is append-only and
content-addressed: each record is keyed `id#fingerprint`, where the fingerprint is taken from the step's input.
`Recipes.Cache`:

| Call | Does |
|---|---|
| `is_current(id, fingerprint)` | whether the store already holds this exact input's output (then the step skips itself) |
| `put(id, fingerprint, bytes)` | appends the output, unless an identical entry is there |
| `read(id)` | the current output for an id, from the store |

Beside it, `store.bin.index` lists every record's key, offset and length, so opening the store is one read, not a
scan; if it is missing or disagrees with the store's size, the store is rescanned and the index rewritten.

Each executable keeps a small `.slop-index-<executable>.json` beside its program: which fingerprint each id
currently means for it. A second run builds nothing, and a program whose inputs another program already cooked builds
nothing either. The index is per executable, not per program folder, because several builds of one program (a
player's client beside test clients) can run from the same folder with different code, and each keeps the assets
it was cooked with.

**Several processes share one store safely.** Every write, and every rescan with its index rewrite, holds an
exclusive lock on `store.bin.lock` (`Recipes.StoreLock`, `LockFileEx`), so appends never interleave. Each read also
checks that the header at its offset names the key it asked for and the same length, and crashes
naming both if not (`store_entry_at_its_offset_is_the_key_asked_for`), so a damaged store is loud.
`examples/store_race_test` has four processes write 2,000 records each at once and reads all 8,000 back.

**A format change re-cooks by itself.** `Pack<T>` writes the asset's kind and its schema, the hash
`BinaryWriter<T>.schema()` works out from the class's attributes, after the
`SLOP` header, and `decode` refuses bytes whose schema differs instead of misreading them. `put` stamps each
record as `id#fingerprint#kind#schema`, and `is_current` compares that stamp with the schema of the kind as the
program is compiled now; the cache knows every schema by walking the classes in `asset/` folders. So adding a field
to `Asset.Mesh` makes every mesh stale on the next run and it re-cooks, with no version string to bump. Bytes not
written by `Pack` (compiled shaders, for example) are stamped with an empty kind and schema 0. Stale records stay
in the append-only store.

## Worktrees and shared cooking

A worktree is nearly free. Godot and Unreal copy every asset and all the code into a new worktree; a SlopEngine
worktree holds only the files it changes, and everything else loads from the original.

- **Assets.** A program names its base by declaring `func base_folder(): String` in its `build.spite`; a program
  that declares none has no base. `Sources` looks in the
  program first and the base second, so a changed PSD in the worktree wins and the rest are the base's. Cooking goes
  into the base's store: unchanged inputs have the same fingerprint and are already there; a changed one appends a
  new record beside the old, so the base and every worktree stay valid at once.
- **Code.** A worktree is a folder whose entry loads its base (`load "../click_counter"`) and reopens only the
  classes it changes.

`click_counter_test` and `render_parity` work this way over `click_counter`: both declare it as their `base_folder()`,
and neither cooks anything once the game has.

## Hot reload: change a source, see it in the game

A running program picks up an artist's change without restarting and without a stutter. Two sides, joined only by
the cache's files on disk:

**The cook watches its sources.** While `cookbook.cook()` runs a recipe, every source file it opens (`Psd.Layers.open`,
`Recipes.Glsl.compile`, or a recipe's own `cookbook.note_source(path)`) is recorded against it in
`Recipes.Cookbook` with its `File.modified()` and `size()`. `Recipes.Watcher` holds the OS's change notifications
for those folders and needs no thread: each tick it checks them with a zero wait (one cheap system call), and
reports a change once they have been quiet for 100 ms, so a burst of writes is one change. `System.Recook`
(`input`) then compares stamps and submits the stale recipes to the thread pool as a `Recipes.CookTask`; the frame
thread only submits it and, once `finished`, drops the handle. The recipes append their new outputs to the cache binary and rewrite the program's index.

**Textures follow the catalog.** Each texture's `Render.Component.Texture` records the catalog revision it was
loaded at, on the texture's own entity. When `Recipes.Catalog` sees the cache change (below), `FinishTextureLoads` starts
ordinary background loads for the textures whose record changed since. The Vulkan backend re-uploads a slot whose
generation moved and retires the old image, view, memory and descriptor set once the frames using them have finished.

`examples/hot_reload_test` cooks a texture from a one-line text file, rewrites it to red and then to blue while the
app runs, and checks both the software canvas and Vulkan follow; the worst tick while re-cooking and reloading is
2 ms.

**Every store follows the catalog.** `Recipes.Catalog`, which textures, meshes, skeletons, clips, blobs and terrain read
through, watches the cache folder and the program's folder (where its index lives). `System.RefreshCatalog`
(`input`) re-reads the index on a worker when they change, compares each id's fingerprint with the index it had,
and bumps its `revision`, remembering the revision each changed id moved at (`revision_of(id)`). The `Scene.Meshes`
resource (each mesh an entity holding `Scene.Component.Mesh`) and `Recipes.AssetSlots` (skeletons and clips) note
the revision each slot was loaded at; a slot whose id moved since
is loaded again in the background and swapped in, its `generation` moves, and the renderer re-uploads a mesh
whose generation moved. A slot still loading waits for the next pass, so an older load never lands over a newer one.

**Sources a recipe reads are recorded.** `Blend.File.open`, `Psd.Layers.open` and `Recipes.Glsl.compile` note their
files; a recipe that opens a file itself calls `cookbook.note_source(path)`. A source's stamp is its modification
time in nanoseconds and its size: a stamp to the second missed a same-size edit saved within the same second.

`examples/live_asset_test` cooks a mesh and a skeleton from one-line text files, rewrites both while the app runs,
and checks both are swapped in; the worst tick is 1 to 2 ms.

What follows the catalog is textures, meshes, skeletons and clips. A change to a source file re-cooks; a change to a
recipe's own code does not, and fonts and terrain materials are read once.

## Background loading

A game names an asset; the engine loads it without stalling a frame. `Render.Textures().request(id)` (a resource) answers a
slot at once, and gives the texture an entity of its own holding a `Render.Component.Texture`, marked
`Component.Loading` while its job runs. The first request
for an id looks up where its record sits in the cache binary
(an in-memory index, no disk access) and starts a `Parallel` job on its own thread: the job reads the record and
decodes it with `Pack`, which copies the texels in one block, already laid out for the GPU. The frame thread never waits for it:
`FinishTextureLoads` asks each job's thread whether it has finished with a zero-timeout wait and only then takes the
result. The Vulkan backend stages each new texture with one `memcpy` and records its copy into the frame's own
command buffer, so no upload waits on its own fence. Until
the texture's entity has `Render.Component.TextureReady`, `DrawUi` skips it; the Vulkan backend uploads each slot once it is ready;
`FinishTextureLoads` forgets finished jobs.

---

Next: [Loaders](loaders.md), the source formats read in pure Spite.
