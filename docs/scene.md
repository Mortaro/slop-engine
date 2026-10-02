# 3D: scenes, characters and lighting

Built and tested by `examples/kal_character`: a Kal archer read straight from its `.blend`. It is skinned, textured
and animated, lit by the sun, sky and fog, casts a shadow and is tone mapped, with no Blender install and no
exporter. Everything is split into plugins, so a game loads only what it uses and can replace any piece.

The Kal assets are not in this repository. The example reads them from `D:/Projects/kal-assets`; point it elsewhere
with `spite kal_character --kal-assets=<folder>`.

| Plugin | Namespace | What it brings |
|---|---|---|
| `slop_transform_plugin` | `Transform` | `Transform.Component.Transform`: position, a rotation quaternion and scale |
| `slop_camera_plugin` | `Camera` | `Camera.Component.Camera` (eye, target, field of view, near, far) and `Camera.Component.Orbit` with the `AimOrbit` system |
| `slop_scene_plugin` | `Scene` | `Scene.Component.Model` (a mesh id), `Scene.Component.DitherFade`, `Scene.Component.Decal` and `Scene.Component.Unlit` (see [Materials](#materials)) and, on an animated model, `Scene.Component.Skin` (its `Scene.Pose`: the bone palette and each bone's pose, asset data rewritten every frame); `Scene.Component.View` on each window, whose draws, terrain draws and palettes for the frame live in the `Scene.Draws` resource (`draws.of(view)`, a `Scene.DrawSet` per view); the `Scene.Meshes` and `Scene.TerrainMaterials` resources, which give each mesh and terrain material an entity (`Scene.Component.Mesh`, `Scene.Component.TerrainMaterial`, marked `Component.Loading` while a job runs and `TerrainTexturesRequested` once its control textures are asked for); and `Scene.Component.ViewCamera` (the view matrix, field of view, near, far, eye and shadow centre) while a camera exists; `Gather` collects the camera, the models and the lighting every frame |
| `slop_scene_vulkan_plugin` | `SceneVulkan` | the Vulkan passes: sun shadow map, lit scene into HDR, decals and translucent sections over it, tone map into the frame, then the UI draws on top; `SceneVulkan.MeshRenderer` is a resource (singleton) holding the passes and the per-frame buffers; each mesh's entity gets `SceneVulkan.Component.GpuMesh` (its vertex and index buffers) and each texture's `SceneVulkan.Component.SceneTexture` (its scene-sampler descriptor set); `SceneVulkan.Component.MeshRendererCreated` marks the world entity once the passes are built |
| `slop_animation_plugin` | `Animation` | `Animation.Component.Animator` (skeleton, clip, time, speed), looping unless the entity has the marker `Animation.Component.PlayOnce`; `Animate` samples the clip into the model's `Skin`, adding one the first time |
| `slop_lighting_plugin` | `Lighting` | `Sun`, `Sky`, `HeightFog` and `Exposure` components and a `Daylight` bundle, written into each view; `PointLight` and `SpotLight` components gathered into `Scene.Lights` |
| `slop_blend_plugin` | `Blend` | `MeshReader`, `SkeletonReader` and `ActionReader`: what a recipe needs from a `.blend` |
| `slop_png_plugin` | `Png` | a PNG decoder, pixel-exact against Pillow, for the images packed in a `.blend` |

`slop/` itself gains only neutral pieces:
- the assets: `Asset.Mesh` (with an `Asset.Material` per slot), `Asset.Skeleton` and `Asset.Animation`;
- `Recipes.AssetSlots<T>`, which loads any cooked asset on the thread pool;
- the maths: `Math.Scalar`, `Math.Matrix4`, `Math.Pose` and `Math.Vector3`.

## A character is cooked by a recipe

`kal_character/recipe/archer.spite` opens `archer.blend` once, then cooks:
- the skeleton from the `rig` armature;
- the outfit's parts, each `Body - <part>` object into `archer.body.<part>`;
- each part's packed PNG into `archer.texture.<image>`;
- the `Idle`, `Walk` and `Run` actions into `archer.animation.<clip>`.

A recipe is plain Spite, so choosing parts, naming ids and grouping outfits belong to the game, not to the loader.
The whole archer (65 bones, seven parts, three clips) cooks in about 5.5 s, 4.3 s of which is decompressing the
zstd `.blend`, and only when the file's size or modification time changes.

What the readers do:

- **Pointers are resolved within the ID being read.** Blender 5 reuses pointer values across data-blocks, so a
  reader enters the ID it reads (`file.enter(view)`) and duplicate addresses resolve to that ID's blocks.
- **Meshes.** Blender 5 keeps geometry in `AttributeStorage`: `position`, `.corner_vert`, the active UV map and
  `sharp_face`. Each attribute's data sits behind an `AttributeArray`.
  - Faces are triangulated as fans.
  - Normals are smooth, or the face normal where `sharp_face` is set.
  - Corners are welded by vertex, normal and UV.
  - Positions go through the object's world matrix and from Blender's Z-up to Y-up, `(x, y, z) → (x, z, -y)`.
  - Skin weights come from the deform-vertex layer of the vertex data: the four heaviest groups that name a
    bone, renormalised. A mesh with no deform layer is static: it gets no joints, so it is drawn with the identity
    palette entry. A vertex of a skinned mesh that no group weighs follows bone 0.
  - Faces are grouped by their `material_index`, one section per material slot. `Asset.Mesh.sections` holds
    three numbers per section (first index, index count, material slot), and `Asset.Mesh.textures` one texture
    id per material slot, which the recipe fills.
  - Each material's base image is the image-texture node linked to the Principled BSDF's Base Color.
    `MeshReader.images` has the image's name per slot, `image_bytes` its packed file, and `image_paths` the file
    path when the image is not packed (an external `.psd`, for example), so the recipe can cook it. The path is
    Blender's own form, the SDNA field `name`: relative to the `.blend` with a leading `//`, and backslashes on
    Windows.
  - The rest of each material goes into `Asset.Mesh.materials`, one `Asset.Material` per slot (see
    [Materials](#materials)). Every other image a material uses (normal, roughness, metallic, emission and opacity
    maps) is listed once in `MeshReader.map_images`, with `map_image_bytes` and `map_image_paths`; the material
    names it by its image name until the recipe cooks it and calls `mesh.rename_map(image, id)`.
  - A socket fed by a node the reader does not understand crashes the cook, so a material is never drawn wrong in
    silence.
  - Tangents are computed for every vertex the MikkTSpace way, as Blender bakes normal maps: per triangle from the
    texture coordinates, weighted by the corner's angle, made perpendicular to the normal, with the bitangent's sign
    in `w`. A vertex whose triangles disagree on that sign is split. They are in `Asset.Mesh.tangents`, four floats
    per vertex; a mesh without them gets a tangent perpendicular to its normal when it loads.
  - A hand-built mesh adds a section with `mesh.add_section(first, count, texture)`, or with its material with
    `mesh.add_material_section(first, count, texture, material)`.
  - The renderer draws each section on its own, with its own material.
- **Skeletons.** Bones are ordered so parents come first. The inverse bind is
  `(to_target · armature_world · arm_mat · to_source)⁻¹`.
- **Actions.** Layered actions (layers, strips, channel bags) and legacy `curves` are both read.
  - Location, quaternion rotation and scale F-curves are evaluated at every whole frame: constant, linear, and
    bezier through a cubic solved for the frame.
  - Each frame is posed in Blender's armature space: `pose[parent] · rest[parent]⁻¹ · rest · basis`.
  - The pose is moved to engine space and stored as the parent-relative position, rotation and scale.

## Animation

`Animate` advances each animator by the tick's step (the world entity's `Component.Frame.step_milliseconds`) and
samples its clip. The step is measured once per tick, so every part of a character advances by the same amount.

- Position and scale are interpolated linearly.
- Rotation uses a shortest-arc slerp, falling back to a normalised lerp for near-identical keys.
- It writes `global · inverse_bind` for each bone into the `Skin`'s `pose.palette`, and each bone's model-space pose
  (`global`) into `pose.bones`.
- It skips a model marked `Scene.Component.OffView`. Gather adds that marker when a skinned model leaves the view
  cone and its shadow cannot reach the view (its sphere swept away from the sun), and removes it when either comes
  back, so an off-screen character costs no sampling and the marker changes only on those crossings. A character
  coming into view shows its last pose for one frame.
- An animator on the same skeleton, clip, time and `PlayOnce` as the one sampled just before it copies that pose
  instead of sampling. The parts of one character are spawned together and sit next to each other in the row, so a
  seven-part archer samples once.
- The palette and bones matrices are rewritten in place, and the inverse binds are multiplied straight from the
  skeleton's floats, so a frame allocates nothing per bone.

`examples/animate_bench` animates 400 seven-part archers (2,800 animators, 65 bones) in rings around the camera,
each archer at its own time. Optimised, on an RTX 3090 machine: Animate takes 9 ms, GatherModels 6.6 ms and
DrawScene 5.7 ms (727 of 2,800 models drawn), a 26 ms frame.

### Bone attachments

A weapon, a shield or an effect rides a bone of another entity's animated skeleton. Give it a `Transform`, an
`Animation.Component.BoneAttachment`, and make it a child of the carrier:

```gdscript
var sword = carrier.create_entity()
var attachment = Animation.Component.BoneAttachment()
attachment.bone = "Bip01 R Hand"
attachment.rotation_z = 0.7071068
attachment.rotation_w = 0.7071068
sword.add_component(attachment)
sword.add_component(model)
sword.add_component(transform)
```

How it's resolved:
- **Placement:** each frame, `FollowBones` (`prepare`, after `Animate`, before the scene is gathered) writes the
  attachment's `Transform` in world space: the carrier's `Transform`, times the bone's pose, times the attachment's
  offset (position, rotation, scale in the bone's space).
- **Which bone:** name the bone with `bone`, or give `bone_index` (0 or more) for an index, as monsters' effect bones
  are. The name is looked up once in the carrier's skeleton and cached against the name, so changing `bone` later
  looks it up again. A name the skeleton doesn't have crashes, naming the bone and the skeleton.
- **The carrier:** it needs an `Animator`, a `Skin` and a `Transform`. Until its skeleton has loaded and been posed,
  the attachment keeps its own `Transform`.
- **Despawning:** because the attachment is a child, it despawns with its carrier.

`examples/attachment_check` checks a named bone with an offset and an indexed bone on a synthetic, turned skeleton.

The scene plugin knows nothing of animation: it uploads the palette of any model with a `Skin`, and the vertex shader skins
with four bones per vertex.

## Lighting

The scene pass writes pre-exposed radiance into an RGBA16F image. The maths:
- **Specular:** GGX distribution, height-correlated Smith visibility, Schlick Fresnel with grazing reflectance.
- **Diffuse:** Lambert.
- **Material:** each section's own, below; a mesh that names none gets roughness 0.7, specular 0.5, metallic 0.
- **Ambient:** a sky and ground hemisphere.
- **Fog:** exponential height fog by its optical depth along the view ray.
- **Exposure:** `1 / (1.2 · 2^EV100)`, with EV100 15 by default.

A full-screen pass tone maps with the ACES fit, encodes sRGB and dithers into the frame, under the UI.

The sun casts a 2048² shadow map:
- an orthographic view around the camera's target, with the depth-only pipeline sharing the skinning vertex
  shader and keeping alpha cut-outs;
- a slope-scaled depth bias against acne;
- 3×3 PCF when sampling.

### Materials

`Asset.Material` is what the reader takes from a Principled BSDF (the node feeding the Material Output's Surface):

| Field | From the `.blend` | Default |
|---|---|---|
| `base_red`, `base_green`, `base_blue` | Base Color when no image feeds it (linear) | 1 (the image alone) |
| `normal`, `normal_strength` | a Normal Map node in tangent space feeding Normal: its Color image and Strength | none |
| `roughness`, or `roughness_map` and `roughness_channel` | Roughness: its value, or the image (or one channel of it) feeding it | 0.7 |
| `metallic`, or `metallic_map` and `metallic_channel` | Metallic, the same way | 0 |
| `specular` | Specular IOR Level | 0.5 |
| `emissive_red`, `emissive_green`, `emissive_blue`, `emissive_map` | Emission Color times Emission Strength, or the image feeding Emission Color times the strength | 0 |
| `opacity`, or `opacity_map` and `opacity_channel`, or `opacity_from_base` | Alpha: its value, an image, or the base image's own alpha | 1 |
| `two_sided` | off when the material's Backface Culling is on | on |
| `translucent` | the material's Render Method is Blended | off |
| `unlit` | the Surface is an Emission node: its Color (an image, read as the base image, or a colour) times its Strength | off |
| `scroll_across`, `scroll_down`, `pulse_speed`, `pulse_minimum` | set by the recipe | none |

The Surface may also be a Mix Shader of a Transparent BSDF (its first shader) and a Principled BSDF or an Emission
(its second): the material is the second one's, with the Mix's factor as its opacity. With the Blended render
method, a Transparent and Emission mix whose factor is an image's alpha is Blender's unlit, translucent, emissive
material.

A map's channel is 0 to 3: an image's Color reads red (a greyscale map), its Alpha reads alpha, and a Separate Color
(or Separate RGB) node picks one channel, so one packed occlusion, roughness and metallic image feeds both maps.

How the scene shader uses it:

- **Normal maps** are tangent space, green up, as Blender's: the bitangent is `w · (N × T)`, and the strength mixes
  the mapped normal with the surface's.
- **Emission** is luminance in nits, exposed like the sun and sky, and added to the lit colour. An **unlit**
  material is its base colour times its emission, with fog and nothing else.
- **One-sided** sections cull their back faces in the scene pass; two-sided ones are lit on both sides. The shadow
  pass draws both faces of everything.
- **Translucent** sections are blended over the opaque scene after it, sorted back to front by their model's
  origin, with depth test and no depth write. Their colour is lit like an opaque one and covers by its opacity.
  They cast no shadow.
- **Time:** the texture coordinates move by `scroll_across` and `scroll_down` texture widths per second, and the
  opacity is multiplied by `pulse_minimum + (1 - pulse_minimum) · (0.5 + 0.5 · sin(2π · pulse_speed · t))`, `t`
  being the game clock (`world.now()`). Both are computed per frame in double precision, so they never jump.

A material with no maps and not unlit is drawn by a lean variant of the scene shader (a specialisation constant
leaves the map code out), so plain materials cost what a one-texture shader does.

### Masked materials

A material is masked when its Principled BSDF's Alpha is linked and it is not translucent; the reader lists its slot
in `Asset.Mesh.masked_materials`. A masked section's pixels whose opacity is below 0.3333 are discarded in every
pass, as Unreal's masked materials clip; every other section is opaque and never discards, whatever its texture's
alpha. A hand-built masked section with no opacity source clips on its base image's alpha. Mipmapping averages a
cut-out's alpha, so at a distance chain mail and straps read as solid, as they do in Unreal.

### Dither fade

`Scene.Component.DitherFade { opacity }` on a model's entity fades it the way Unreal's occluder dither does: a 4×4
ordered (Bayer) pattern keeps a pixel when its threshold is under the opacity, in the scene and the shadow pass
alike, so the model and its shadow thin out together. The default opacity is 0.65, Unreal's occluder fade. Remove
the component to draw the model whole again.

```gdscript
var fade = Scene.Component.DitherFade()
fade.opacity = 0.65
wall.add_component(fade)
```

### Decals

A decal is an entity with a `Transform` and a `Scene.Component.Decal`; its box is the unit cube scaled, turned
and placed by the transform, and it projects along its local y (down, unturned). After the opaque scene, the decal
pass draws each box's back faces and, for every pixel, finds the surface behind it from the depth buffer; a surface
inside the box takes the decal, with the box's local x and z (from −0.5 to 0.5) as its texture coordinates.

| Field | Means |
|---|---|
| `texture` | the image id; empty for plain colour |
| `red`, `green`, `blue` | the tint, multiplying the image |
| `opacity` | multiplies the image's alpha; the result covers the surface |
| `emissive` | luminance in nits of the tinted image, added to it |

The tinted image is lit like an opaque surface (sun and its shadow, lights, sky), with the surface's normal taken
from the depth buffer. A decal entity with the marker `Scene.Component.Unlit` adds only its emission: an unlit,
translucent, emissive decal such as a selection ring under a target. Emission is exposed like daylight, so under the
default EV100 of 15 it takes about 20,000 nits to read as bright as a sunlit white surface.

```gdscript
var ring = world.create_entity()
var decal = Scene.Component.Decal()
decal.texture = "texture.select_ring"
decal.red = 1.0
decal.green = 0.05
decal.blue = 0.05
decal.emissive = 20000.0
ring.add_component(decal)
var unlit = Scene.Component.Unlit()
ring.add_component(unlit)
```

A decal is culled against the view like a model, by the sphere around its box. `Scene.LoadedMesh` keeps the
bind pose's half extents (`half_x`, `half_y`, `half_z`) beside its bounding sphere, so a decal can be sized to a
mesh's footprint.

**Texture filtering.** Every texture is uploaded with a full mip chain, made on the GPU by blitting each level from the
one above. Scene textures sample trilinearly with 16× anisotropic filtering (when the device has it) and repeat
addressing. The UI samples the same images through its own nearest, top-level-only sampler, so it stays pixel-exact.

### Culling and draw distance

Each loaded mesh keeps a bounding sphere of its bind pose, and a skinned mesh the joints its vertices weigh. A skinned
model's sphere follows its pose: each used joint's skinning matrix carries the bind-pose centre, and the sphere around
the box of those centres, grown by the bind-pose radius, holds every vertex, since a skinned vertex is a weighted mix
of rigid moves. Scene Gather tests every model and terrain cell against the camera's view cone, and drops what is
behind it, beside it or past its far plane (`Camera.far`), so a far plane at the horizon costs only what is in
view. Depth is reversed-Z, so a 20 km far plane keeps its precision. A terrain cell may name a coarser `far_mesh`,
drawn once the cell is `far_distance` metres away.

**Instancing.** Draws of the same mesh section share a texture, so the renderer counting-sorts them by (mesh, section)
into contiguous runs of the draw buffer and issues one instanced draw per run; the vertex shader reads
`draws[push.draw + gl_InstanceIndex]`, and skinned instances keep their own palettes. `examples/props_bench` draws
17,000 cubes (11,192 in view) in a 13.9 ms frame, `DrawScene` taking 2.2 ms (optimized, RTX 3090).

### Terrain

A terrain cell is an entity with a `Transform` and a `Scene.Component.TerrainCell { mesh, material }`, with no
`Model`: it is drawn by the terrain pipeline, which shares the scene's vertex shader, lighting, shadows and fog
(`lit.glsl`). The shader ports a splat-index Unreal terrain material formula for formula:

- **Control textures:** control UV = world x/z ÷ (`control_width`, `control_depth`). The tile's eight layer slots come
  from `control_a` (slots 0–3) and `control_b` (4–7), read unfiltered (slice = texel × 255). Their tiling comes from
  `scale_a`/`scale_b`, filtered (tiles per metre = texel × `layer_scale`).
- **Blend:** slot 0 is the base; slots 1–7 paint over it in order, `lerp(colour, layer_k, weight_k)`, with weights
  from `splat_0` (rgba) and `splat_1` (rgb).
- **Detail:** colour × `1 + (detail − 0.5) × detail_strength × clamp(1 − depth / detail_fade_depth)`.
- **Grass tint:** `grass_overlay` × luminance × `grass_overlay_brightness`, mixed in by `grass_mask` ×
  `grass_mask_strength` × a smoothstep of the normal's world-up between `grass_slope_low` and `grass_slope_high`.
- **Far colour:** optional, faded in from `far_fade_start` to `far_fade_end`. Roughness and specular are per
  material.

`Asset.TerrainMaterial` names its textures by id:
- the layer, normal, detail, overlay and far-colour images are `Asset.TextureArray`s (RGBA8, layer-major), which
  upload one layer per frame, each with its mipmaps made on the GPU;
- the control, scale, splat and mask images are ordinary `Asset.Texture`s.

A material is drawn once every array and texture has arrived; until then its cells are skipped, so nothing waits.
`examples/terrain_check` cooks a two-by-two-tile fixture and checks that each tile's base layer and a painted splat
land where the formula puts them.

### Point and spot lights

Put a `Lighting.Component.PointLight` or `SpotLight` on an entity with a `Transform`. The fields are:
- `red`, `green`, `blue`: linear colour;
- `intensity`: in candela;
- `range`: in metres, where the light fades to exactly zero.

A spot also has `inner_angle` and `outer_angle`, in radians from its axis. It shines along its transform's −Z.

```gdscript
var torch = world.create_entity()
var light = Lighting.Component.PointLight()
light.intensity = 3.0
light.range = 6.0
torch.add_component(light)
torch.add_component(transform)
```

How a light is shaded:
- **Falloff:** inverse square, floored at 1 cm and windowed to zero at the range (Karis 2013).
- **Cone:** a spot's cone is `clamp(cos · scale + offset)²` (Frostbite).
- **Surface response:** the same GGX and Lambert as the sun.

Each frame:
1. `ClearLights` (`prepare`) empties the `Scene.Lights` resource (a singleton: the lights are gathered once, not per window).
2. `GatherPointLights` and `GatherSpotLights` (`render`) stream every light into it, 16 floats each.

Only the position is read, so a light that is a child of a moving entity needs its own transform kept in world
space.

**Clustered forward shading.** `Scene.LightClusters` cuts each view into 16×9 tiles and 24 exponential depth slices
from 0.5 m to the camera's far plane, on the CPU:
- A light whose sphere is behind the camera, past the far plane or outside a side plane is culled.
- Every other light is added to the clusters its bounds reach in each slice it spans.
- A count pass and a write pass put exact per-cluster lists into the GPU buffers; nothing is capped or dropped.

The scene shader finds its fragment's cluster from the view-space position and loops over that cluster's lights only.
Set 1 carries them in bindings 4 (visible lights, 64 bytes each), 5 (a first/count pair per cluster) and 6 (the light
index array). All three are host-visible per frame in flight, and the light and index buffers grow when a frame needs
more.

`examples/lights_check` lights a dark floor with a red point light and a blue spot. It checks the pixel under the
point light is lit red and a far corner stays dark. Set `extra_lights` in its environment to add a grid of point
lights for timing.

With 3,000 lights (79 on screen, 12,853 cluster entries), on an RTX 3090 with validation on:
- the clusters and their upload cost about 0.22 ms of the scene system;
- gathering costs 0.33 ms (optimized).

Point and spot lights cast no shadows.

Lighting data lives on the neutral `Scene.View` with daylight defaults. The lighting plugin only overwrites it from
components, so a scene without that plugin is still lit.

---

Next: [Environments and networking](networking.md), one program built as a client, a server and a bot.
