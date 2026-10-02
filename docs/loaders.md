# Loaders in pure Spite

No installed software is needed to read a source file. Each format is Spite code, reverse-engineered where it had to
be, and checked against a reference.

`slop/` knows no source format. It knows only the assets it contributes (`Asset.Bytes`, `Asset.Texture`, and the 3D
assets of [scene.md](scene.md)), and each loader is a plugin a program or a theme loads when one of its recipes reads that format:

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
  the plugin loads `slop_png_plugin`. Each channel decodes into a plane of bytes (a PackBits run is one copy or one
  fill), and the planes interleave straight into the texture's `texels`, applying the transparency channel (`-1`) and
  the layer mask: an RGBA8 `Asset.Texture`; a 16-bit sample keeps its high byte.
- A flat document, with no layer section and only the merged image (what Photoshop writes for a single-image file,
  and the only part Blender and OpenImageIO read), shows as one layer named `Background` covering the canvas.
  Its channels are red, green, blue and an optional transparency, sharing one compression: raw, PackBits with every
  channel's row counts first, or one ZIP stream for all channels, inflated once.
- Everything outside that subset (32 bit, CMYK, `.psb`) crashes naming the reason.

Checked: the three primary button plates of `buttons.psd` match a reference decoder's output pixel for pixel, and
`psd_zip_probe` decodes sixteen generated files (layered and flat, 8 and 16 bit, each of the four compressions) to the checksum
`make_fixtures.py` works out for them.

Speed (optimized, Ryzen 9 5950X): a 3328×3584 terrain splat map (PackBits, 10 MB) opens in 3 ms and decodes in
40 ms, about 3.4 ns a pixel; a 4096×4096 ZIP-compressed normal map decodes in 91 ms. That is paid once, when a
recipe cooks.

## zstd (`slop_zstd_plugin`)

RFC 8878, because every `.blend` Blender 5 saves is zstd-compressed.

- frames and skippable frames (Blender's seek table), raw, RLE and compressed blocks;
- literals: raw, RLE, and Huffman in one or four streams, with FSE-compressed or direct weights;
- sequences: predefined, RLE, FSE-described and repeated tables, and the three repeat offsets.

`Zstd.BitReader` reads the backward bit streams with the standard library's bitwise functions. Checked: byte-identical with Zig's
standard-library decoder on a 261 MB archer file, in 0.86 s.

## .blend (`slop_blend_plugin`)

Blender 5.2's format (`BLENDER17-01`): a 17-byte header, then blocks with 32-byte headers (code, SDNA index, old
address, 64-bit length and count).

- `Blend.File.open(path)` decompresses when needed, reads every block, maps old addresses to blocks, and parses the
  `DNA1` block: names, types, sizes and structs, with each field's offset computed from its type and array
  dimensions.
- `Blend.View` reads any field by name (`integer`, `short_integer`, `small_integer`, `float_at`, `pointer`, `text`),
  descends into an embedded struct (`inner`), follows a pointer (`follow`) and steps through arrays (`element`).

What it has found in Blender 5.2: a mesh's data is in `AttributeStorage`, as named attributes, each with its type
(`data_type`: 0 boolean, 2 int16 pair, 3 int, 4 int pair, 7 float3) and domain (`domain`: 0 point, 1 edge, 2 face,
3 corner): `position` (float3 per vertex), `.edge_verts` (int pair per edge), `.corner_vert` and `.corner_edge` (int
per corner), `UVMap` (float2 per corner), `sharp_face`, `sharp_edge`, and `custom_normal`, either int16 pairs per
corner (Blender's encoded custom normals, which `normals_split_custom_set` and the Weighted Normal modifier write)
or float3 "free" normals on the point, face or corner domain; face offsets are in `poly_offset_indices`.

Meshes, skeletons, skins, animations and packed PNG textures are read by the readers in [scene.md](scene.md).
Faces are triangulated and corner normals worked out the way Blender does it (see [scene.md](scene.md)). One UV
set is read and vertex colours are ignored, and an image that references an external file is reported by its path
for the recipe to cook.

Checked: `blend_mesh_check` reads thirteen meshes `make_fixtures.py` builds in Blender 5.2 (concave L, U, star,
comb and spiral n-gons, collinear points, a folded quad, smooth and sharp-edged spheres, encoded, weighted and free
custom normals, a rotated and unevenly scaled object) and compares every triangle corner's position and normal
with the loop triangles and corner normals Blender itself reports.

---

Next: [3D](scene.md), characters cooked from `.blend`, animation, lighting and terrain.
