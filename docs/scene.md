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
| `slop_scene_plugin` | `Scene` | `Scene.Component.Model` (a mesh id) and, on a skinned model, `Scene.Component.Skin` (its `Scene.Pose`: the bone palette it is drawn with, and each bone's pose); `Scene.Component.View` on each window, whose draws, terrain draws and palettes for the frame live in the `Scene.Draws` resource (`draws.of(view)`, a `Scene.DrawSet` per view); the `Scene.Meshes` and `Scene.TerrainMaterials` resources, which give each mesh and terrain material an entity (`Scene.Component.Mesh`, `Scene.Component.TerrainMaterial`, marked `Component.Loading` while a job runs and `TerrainTexturesRequested` once its control textures are asked for); and `Scene.Component.ViewCamera` (the view matrix, field of view, near, far, eye and shadow centre) while a camera exists; `Gather` collects the camera, the models and the lighting every frame |
| `slop_scene_vulkan_plugin` | `SceneVulkan` | the Vulkan passes: sun shadow map, lit scene into HDR, tone map into the frame, then the UI draws on top; `SceneVulkan.MeshRenderer` is a resource (singleton) holding the passes and the per-frame buffers; each mesh's entity gets `SceneVulkan.Component.GpuMesh` (its vertex and index buffers) and each texture's `SceneVulkan.Component.SceneTexture` (its scene-sampler descriptor set); `SceneVulkan.Component.MeshRendererCreated` marks the world entity once the passes are built |
| `slop_animation_plugin` | `Animation` | headless, so a server loads it too: `Animation.Component.Animator` (skeleton, clip, loop start, time, speed, weight), looping unless the entity has the marker `Animation.Component.PlayOnce`; `Animate` samples it into `Animation.Component.Pose` (the bone palette and each bone's pose, asset data rewritten every frame), adding one the first time; blend layers, crossfades, throttling and bone attachments ([below](#animation)) |
| `slop_scene_animation_plugin` | `SceneAnimation` | what joins the two: an animated model's `Scene.Component.Skin` shares its `Animation.Component.Pose`, and `Scene.Component.OffView` marks it `Animation.Component.Unseen` |
| `slop_lighting_plugin` | `Lighting` | `Sun`, `Sky`, `HeightFog` and `Exposure` components and a `Daylight` bundle, written into each view; `PointLight` and `SpotLight` components gathered into `Scene.Lights` |
| `slop_blend_plugin` | `Blend` | `MeshReader`, `SkeletonReader` and `ActionReader`: what a recipe needs from a `.blend` |
| `slop_png_plugin` | `Png` | a PNG decoder, pixel-exact against Pillow, for the images packed in a `.blend` |

`slop/` itself gains only neutral pieces:
- the assets: `Asset.Mesh`, `Asset.Skeleton` and `Asset.Animation`;
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
  - Each material's image is the image-texture node linked to the Principled BSDF's Base Color. A Base Color
    fed by anything but an image node crashes the cook, so a material the reader does not understand is never drawn
    wrong in silence. `MeshReader.images` has the image's name per slot,
    `image_bytes` its packed file, and `image_paths` the file path when the image is not packed (an external
    `.psd`, for example), so the recipe can cook it. The path is Blender's own form, the SDNA field `name`:
    relative to the `.blend` with a leading `//`, and backslashes on Windows. Only the Base Color image is read. A
    hand-built mesh adds a section with `mesh.add_section(first, count, texture)`.
  - The renderer draws each section on its own, with its own texture.
- **Skeletons.** Bones are ordered so parents come first. The inverse bind is
  `(to_target · armature_world · arm_mat · to_source)⁻¹`.
- **Actions.** Layered actions (layers, strips, channel bags) and legacy `curves` are both read.
  - Location, quaternion rotation and scale F-curves are evaluated at every whole frame: constant, linear, and
    bezier through a cubic solved for the frame.
  - Each frame is posed in Blender's armature space: `pose[parent] · rest[parent]⁻¹ · rest · basis`.
  - The pose is moved to engine space and stored as the parent-relative position, rotation and scale.

## Animation

The animation plugin is headless: it needs only `slop/`, `slop_transform_plugin` and `slop_camera_plugin`, so a
server can animate the skeletons its hit boxes and bone attachments ride. A program that draws its characters also
loads `slop_scene_animation_plugin`, which hands each animated model's pose to the scene.

`Animate` advances each animator by the tick's step (the world entity's `Component.Frame.step_milliseconds`) and
samples its clip. The step is measured once per tick, so every part of a character advances by the same amount.

- Position and scale are interpolated linearly between keys.
- Rotation uses a shortest-arc slerp, falling back to a normalised lerp for near-identical keys.
- It writes `global · inverse_bind` for each bone into `Animation.Component.Pose`'s `matrices.palette`, and each
  bone's model-space pose (`global`) into `matrices.bones`. The scene's `Skin` shares those two lists, so nothing is
  copied for drawing.
- An animator on the same skeleton, clip, time, crossfade and `PlayOnce` as the one sampled just before it copies
  that pose instead of sampling. The parts of one character are spawned together and sit next to each other in the
  row, so a seven-part archer samples once.
- The palette and bones matrices are rewritten in place, and the inverse binds are multiplied straight from the
  skeleton's floats, so a frame allocates nothing per bone.

### Looping and loop start

A clip's frames are its keys, first to last, so a looping clip lasts from its first key to its last one:
`(frame_count - 1) / frames_per_second` seconds. Its first and last keys are the same moment of the cycle, so the
loop never plays both: at the end it goes straight on from the first key's pose, and nothing is interpolated back
from the last key to the first. So a looping action ends on the pose it starts with, as a cyclic Blender action
does.

`loop_start` (seconds, 0) on the animator makes a clip play its intro once, then loop from there: a time past the
end comes back to `loop_start`, not to 0. The animator's `time` is kept inside the clip each time it is sampled, so
it stays small however long the clip plays. With `PlayOnce`, the clip stops on its last key.

```gdscript
var animator = Animation.Component.Animator()
animator.skeleton = "archer.skeleton"
animator.clip = "archer.animation.cast"
animator.loop_start = 0.4
caster.add_component(animator)
```

### Blending clips

Clips blend with weights. The animator's own clip counts with its `weight` (1), and each extra clip is a layer: a
child entity of the animated one holding `Animation.Component.Layer` (clip, loop start, time, speed, weight). A
layer advances its own time, loops unless it has `PlayOnce`, and is despawned with its animated entity.

```gdscript
var aiming = archer.create_entity()
var layer = Animation.Component.Layer()
layer.clip = "archer.animation.aim"
layer.weight = 0.5
aiming.add_component(layer)
```

The blended pose is the weighted average of every clip's pose, bone by bone: positions and scales are averaged, and
rotations are summed on the same hemisphere and normalised. So two clips at equal weights give their midpoint, an
animator of weight 3 with a layer of weight 1 lands a quarter of the way to the layer, and a layer of weight 0 counts
for nothing. Changing a weight is writing it. An animator with layers is sampled on its own, never copied from the
one before it. `GatherLayers` (`after_input`) collects each animated entity's layers into the `Animation.Layers`
resource every tick, since a component holds no list.

### Crossfades

To change clip smoothly, add `Animation.Component.Crossfade` (clip, loop start, duration in seconds, 0.25) to the
animated entity:

```gdscript
var fade = Animation.Component.Crossfade()
fade.clip = "archer.animation.run"
fade.duration = 0.3
archer.add_component(fade)
```

- While it lasts, `elapsed` grows by each step, the new clip plays from the crossfade's `time` (0) at the
  animator's speed, and the pose blends from the animator's clip to the new one by `elapsed / duration`.
- When `elapsed` reaches `duration`, the animator takes the new clip, its loop start and its time, the `Crossfade`
  is removed, and the entity is marked `Animation.Component.Crossfaded` for one tick, so a system can chain
  what comes next on `Added<Animation.Component.Crossfaded>` or on the marker itself.
- A `Crossfade` added while another is running replaces it, starting again from the animator's clip.

### Throttling and visibility

An animator far away does not need a pose every tick. Give it `Animation.Component.Throttle` and a `Transform`, and
`ThrottleByDistance` (`after_input`) sets its `interval` from its distance to the nearest viewpoint: every camera's
eye, and every entity with a `Transform` and the marker `Animation.Component.Viewpoint` (on a server, an observer's
avatar). The bands come from `Animation.Component.ThrottleBands` on the world entity, which a game adds to change
them:

| Distance (metres, the defaults) | Sampled |
|---|---|
| up to `every_tick_within` (20) | every tick |
| up to `every_second_tick_within` (40) | every 2nd tick |
| up to `every_fourth_tick_within` (80) | every 4th tick |
| farther | every 8th tick |

- A throttled animator is sampled on the ticks where `(Component.Frame.count + phase) % interval` is 0. Its time
  advances on every tick, so the pose it samples is the one an unthrottled animator would show on that tick; in
  between it holds its last pose. Give a character's parts the same `phase` so they are sampled together, and
  different characters different phases to spread the work over the ticks.
- An animator marked `Animation.Component.Unseen` is not sampled at all, but its time, its crossfade and its layers
  keep advancing, so it shows the right pose the moment it is seen again. `slop_scene_animation_plugin` adds the
  marker when the scene marks a model `Scene.Component.OffView` (it left the view cone and its shadow cannot reach
  the view) and removes it when the model comes back, so a character coming into view shows its last pose for one
  frame. A server marks what no observer sees the same way.
- A `Throttle` on an entity without a `Transform` keeps the `interval` the game writes, so a game can throttle by
  its own rule.
- The first pose is always sampled, whatever the throttle, so a new character never shows its bind pose.

`examples/animation_check` checks blend weights, a crossfade from start to finish, loop wrapping and loop start,
throttled animators against unthrottled ones, and an unseen animator's time, on a synthetic skeleton.
`examples/animation_bench` times `Animate` over 2,800 synthetic animators, 400 seven-part characters in rings 4 to
94 metres from the camera, with and without throttles (`--throttled=true`).

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
- **The carrier:** it needs an `Animator`, a `Pose` and a `Transform`. Until its skeleton has loaded and been posed,
  the attachment keeps its own `Transform`.
- **Despawning:** because the attachment is a child, it despawns with its carrier.

`examples/attachment_check` checks a named bone with an offset and an indexed bone on a synthetic, turned skeleton.

The scene plugin knows nothing of animation: it uploads the palette of any model with a `Skin`, and the vertex shader
skins with four bones per vertex.

## Lighting

The scene pass writes pre-exposed radiance into an RGBA16F image. The maths:
- **Specular:** GGX distribution, height-correlated Smith visibility, Schlick Fresnel with grazing reflectance.
- **Diffuse:** Lambert.
- **Material:** a painted default of roughness 0.7, specular 0.5, metallic 0.
- **Ambient:** a sky and ground hemisphere.
- **Fog:** exponential height fog by its optical depth along the view ray.
- **Exposure:** `1 / (1.2 · 2^EV100)`, with EV100 15 by default.

A full-screen pass tone maps with the ACES fit, encodes sRGB and dithers into the frame, under the UI.

The sun casts a 2048² shadow map:
- an orthographic view around the camera's target, with the depth-only pipeline sharing the skinning vertex
  shader and keeping alpha cut-outs;
- a slope-scaled depth bias against acne;
- 3×3 PCF when sampling.

### Masked materials

A material is masked when its Principled BSDF's Alpha is linked; the reader lists its slot in
`Asset.Mesh.masked_materials`. A masked section's texels with alpha below 0.3333 are discarded in every pass, as
Unreal's masked materials clip; every other section is opaque and never discards, whatever its texture's alpha.
Mipmapping averages a cut-out's alpha, so at a distance chain mail and straps read as solid, as they do in Unreal.
Nothing dithers.

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
