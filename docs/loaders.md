# Loaders in pure Spite

No installed software is needed to read a source file. Each format is Spite code in `slop/`, reverse-engineered where
it had to be, and checked against a reference.

## PSD (`slop/psd/`)

- `Psd.Document.open(path)` reads 8-bit RGB documents: the header, the layer records (bounds, channels, opacity,
  flags, masks, Pascal and Unicode names, group dividers), and builds each layer's `path` (`Plates/Primary/Normal`)
  from the flat, bottom-first record list.
- `pixels_of(layer)` decodes raw and PackBits channels, applies the layer mask to transparency, and answers an
  `Asset.Texture` in straight RGBA.
- Everything outside that subset (16 and 32 bit, CMYK, `.psb`, ZIP channels) crashes naming the reason.

Checked: the three primary button plates of `buttons.psd` match a reference decoder's output pixel for pixel.

## zstd (`slop/zstd/`)

RFC 8878, because every `.blend` Blender 5 saves is zstd-compressed.

- frames and skippable frames (Blender's seek table), raw, RLE and compressed blocks;
- literals: raw, RLE, and Huffman in one or four streams, with FSE-compressed or direct weights;
- sequences: predefined, RLE, FSE-described and repeated tables, and the three repeat offsets.

`Zstd.BitReader` reads the backward bit streams with D117's bitwise functions. Checked: byte-identical with Zig's
standard-library decoder on a 261 MB archer file, in 0.86 s.

## .blend (`slop/blend/`)

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

Not built yet: meshes with Blender's corner normals and triangulation, skeletons, skins, animations, and textures
packed as PNG (which needs inflate).
