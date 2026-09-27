# Loaders in pure Spite

No installed software is needed to read a source file. Each format is Spite code, reverse-engineered where it had to
be, and checked against a reference.

`slop/` knows no source format. It knows only the assets it contributes (`Asset.Bytes`, `Asset.Texture`; a mesh asset
is next), and each loader is a plugin a program or a theme loads when one of its recipes reads that format:

| Plugin | Namespace | Loads |
|---|---|---|
| `plugins/slop_psd_plugin` | `Psd` | nothing else |
| `plugins/slop_zstd_plugin` | `Zstd` | nothing else |
| `plugins/slop_blend_plugin` | `Blend` | `slop_zstd_plugin`, since Blender compresses with zstd |

`click_counter_theme_plugin` loads `slop_psd_plugin` from `theme/theme.spite`, because its recipe cuts `buttons.psd`
into textures; a game using that theme never names the PSD loader itself.

## PSD (`slop_psd_plugin`)

- `Psd.Document.open(path)` reads 8- and 16-bit RGB documents: the header, the layer records (bounds, channels, opacity,
  flags, masks, Pascal and Unicode names, group dividers), and builds each layer's `path` (`Plates/Primary/Normal`)
  from the flat, bottom-first record list.
- `pixels_of(layer)` decodes every channel compression PSD uses: raw, PackBits, ZIP, and ZIP with prediction
  (the row deltas undone per byte at 8 bits and per big-endian sample at 16). ZIP goes through `Png.Inflate`, so
  the plugin loads `slop_png_plugin`. It applies the transparency channel (`-1`) and the layer mask, and answers
  an `Asset.Texture` in straight RGBA; a 16-bit sample keeps its high byte.
- Everything outside that subset (32 bit, CMYK, `.psb`) crashes naming the reason.

Checked: the three primary button plates of `buttons.psd` match a reference decoder's output pixel for pixel, and
`psd_zip_probe` decodes eight generated files (8 and 16 bit, each of the four compressions) to the checksum
`make_fixtures.py` works out for them.

Speed: channels decode into `List<Integer>` one byte at a time. Theseus's `T_TSplat0.psd` (3328×3584, PackBits,
10 MB) opens in 11 ms and decodes in 683 ms, about 57 ns a pixel (2026-09-26, optimized). That is paid once, when a
recipe cooks; decoding straight into the texture's bytes would cut it several times over.

## zstd (`slop_zstd_plugin`)

RFC 8878, because every `.blend` Blender 5 saves is zstd-compressed.

- frames and skippable frames (Blender's seek table), raw, RLE and compressed blocks;
- literals: raw, RLE, and Huffman in one or four streams, with FSE-compressed or direct weights;
- sequences: predefined, RLE, FSE-described and repeated tables, and the three repeat offsets.

`Zstd.BitReader` reads the backward bit streams with D117's bitwise functions. Checked: byte-identical with Zig's
standard-library decoder on a 261 MB archer file, in 0.86 s.

## .blend (`slop_blend_plugin`)

Blender 5.2's format (`BLENDER17-01`): a 17-byte header, then blocks with 32-byte headers (code, SDNA index, old
address, 64-bit length and count).

- `Blend.File.open(path)` decompresses when needed, reads every block, maps old addresses to blocks, and parses the
  `DNA1` block: names, types, sizes and structs, with each field's offset computed from its type and array
  dimensions.
- `Blend.View` reads any field by name (`integer`, `short_integer`, `small_integer`, `float_at`, `pointer`, `text`),
  descends into an embedded struct (`inner`), follows a pointer (`follow`) and steps through arrays (`element`).

What it has found in Blender 5.2: a mesh's data is in `AttributeStorage`, as named attributes: `position` (float3
per vertex), `.corner_vert` and `.corner_edge` (int per corner), `UVMap` (float2 per corner), `sharp_face`,
`sharp_edge`, and `custom_normal` (int16 pairs per corner, Blender's encoded custom normals); face offsets are in
`poly_offset_indices`.

Meshes, skeletons, skins, animations and packed PNG textures are built; see [scene.md](scene.md). Not built yet:
ear-clipping triangulation (faces are split as fans), custom split normals, more than one UV set, vertex colours,
and cooking images that reference external files (the reader reports their paths).
