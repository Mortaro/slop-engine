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
| `slop_scene_plugin` | `Scene` | `Scene.Component.Model` (a mesh id) and, on a skinned model, `Scene.Component.Skin` (its `Scene.Pose`: the bone palette it is drawn with, and each bone's pose); `Scene.Component.View` on each window, whose draws, terrain draws, off-screen shadow casters and palettes for the frame live in the `Scene.Draws` resource (`draws.of(view)`, a `Scene.DrawSet` per view); the `Scene.Meshes` and `Scene.TerrainMaterials` resources, which give each mesh and terrain material an entity (`Scene.Component.Mesh`, `Scene.Component.TerrainMaterial`, marked `Component.Loading` while a job runs and `TerrainTexturesRequested` once its control textures are asked for); and `Scene.Component.ViewCamera` (the view matrix, field of view, near, far and eye) while a camera exists; `Gather` collects the camera, the models and the lighting every frame |
| `slop_scene_vulkan_plugin` | `SceneVulkan` | the Vulkan passes: grass scatter, the shadow atlas (`SceneVulkan.ShadowPass`: the sun's cascades and the point and spot light tiles), lit scene (grass included) into HDR, water, then [post-processing](#post-processing) (`SceneVulkan.PostProcess`: ambient occlusion, temporal anti-aliasing and upsampling, auto exposure, bloom, tone map into the frame), then the UI draws on top; `SceneVulkan.MeshRenderer` is a resource (singleton) holding the passes and the per-frame buffers; each mesh's entity gets `SceneVulkan.Component.GpuMesh` (its vertex and index buffers) and each texture's `SceneVulkan.Component.SceneTexture` (its scene-sampler descriptor set); `SceneVulkan.Component.MeshRendererCreated` marks the world entity once the passes are built |
| `slop_animation_plugin` | `Animation` | headless, so a server loads it too: `Animation.Component.Animator` (skeleton, clip, loop start, time, speed, weight), looping unless the entity has the marker `Animation.Component.PlayOnce`; `Animate` samples it into `Animation.Component.Pose` (the bone palette and each bone's pose, asset data rewritten every frame), adding one the first time; blend layers, crossfades, throttling and bone attachments ([below](#animation)) |
| `slop_scene_animation_plugin` | `SceneAnimation` | what joins the two: an animated model's `Scene.Component.Skin` shares its `Animation.Component.Pose`, and `Scene.Component.OffView` marks it `Animation.Component.Unseen` |
| `slop_lighting_plugin` | `Lighting` | `Sun`, `Sky`, `HeightFog` and `Exposure` components and a `Daylight` bundle, written into each view; `PointLight` and `SpotLight` components gathered into `Scene.Lights` |
| `slop_post_process_plugin` | `PostProcess` | `ToneMapper`, `AutoExposure`, `Bloom`, `Vignette`, `AmbientOcclusion` and `ScreenPercentage` components, written into each view the way the lighting is; see [Post-processing](#post-processing) |
| `slop_foliage_plugin` | `Foliage` | grass types: `Foliage.Component.GrassType`, `DensityMap` and the markers `AlignToSurface` and `RandomYaw`, gathered into the `Scene.Grass` resource ([grass](#grass)) |
| `slop_water_plugin` | `Water` | `Water.Component.WaterBody` and its children's `GerstnerWave`, gathered into the `Scene.Water` resource ([water](#water)) |
| `slop_blend_plugin` | `Blend` | `MeshReader`, `SkeletonReader` and `ActionReader`: what a recipe needs from a `.blend` |
| `slop_png_plugin` | `Png` | a PNG decoder, pixel-exact against Pillow, for the images packed in a `.blend` |
| `slop_texture_compression_plugin` | `TextureCompression` | the cook step that makes a texture's mips and block-compresses them (`Compressor`), and a `Decoder` back to RGBA8 ([assets-and-recipes.md](assets-and-recipes.md#textures-are-cooked-gpu-ready)) |

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
  - Faces are triangulated as Blender triangulates them, so the triangles are Blender's loop triangles in the
    same order and winding: a quad is split along its first diagonal, or the second when the first folds it; a
    larger face is projected onto the plane of its Newell normal and ear-clipped the way Blender's polygon fill
    does, so concave faces and faces with collinear points come out whole.
  - Corner normals are Blender's. A mesh with no sharp edges or faces is smooth (vertex normals weighted by each
    corner's angle); one with every face or edge sharp is flat; otherwise the corners around each vertex are
    grouped into fans split at sharp edges, sharp faces, edges with more than two faces and edges whose faces wind
    opposite ways, and each fan takes the angle-weighted mean of its face normals.
  - Custom split normals (the `custom_normal` attribute) replace them: encoded ones are decoded in each fan's
    normal space, as Blender stores them; free float3 normals are used as they are, per corner, face or vertex.
  - Corners are welded by vertex, normal and UV.
  - Positions go through the object's world matrix and from Blender's Z-up to Y-up, `(x, y, z) → (x, z, -y)`;
    normals go through the inverse transpose of the same matrix, so an unevenly scaled object keeps them
    perpendicular to its faces.
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
- **Exposure:** `1 / (1.2 · 2^EV100)`, with EV100 15 by default, unless the view is
  [metered](#post-processing). The scene is lit already multiplied by it (pre-exposed), so its values stay in the
  range a half float holds.

The scene pass also writes the sky light's share of each pixel into a second target, which ambient occlusion takes
back from. [Post-processing](#post-processing) then turns the HDR image into the frame, under the UI.

### Shadows

The sun and every point or spot light marked `Lighting.Component.CastsShadows` cast shadows. `Daylight` carries the
marker, so its sun casts them, as an Unreal directional light does; a point or spot light opts in, as Unreal's Cast
Shadows does:

```gdscript
var shadowing = Lighting.Component.CastsShadows()
torch.add_component(shadowing)
```

All shadows share one 8192×4096 depth atlas, drawn by `SceneVulkan.ShadowPass` with a depth-only pipeline that
shares the skinning vertex shader and keeps alpha cut-outs, and a slope-scaled depth bias.

**The sun's cascades.** The sun's settings follow Unreal's directional light and its defaults:

| `Lighting.Component.Sun` | Default | Unreal |
|---|---|---|
| `shadow_distance` | 200.0 m | Dynamic Shadow Distance MovableLight |
| `cascade_count` | 3 (at most 4) | Num Dynamic Shadow Cascades |
| `cascade_distribution_exponent` | 3.0 | Cascade Distribution Exponent |
| `cascade_transition_fraction` | 0.1 | Cascade Transition Fraction |
| `shadow_fadeout_fraction` | 0.1 | Shadow Distance Fadeout Fraction |

`LightViews` copies them into each `Scene.Component.View` (with `cascade_count` 0 when the sun has no
`CastsShadows`). Then:
- The view from the camera's near plane to the shadow distance is split as Unreal splits it: cascade `i` ends at
  `near + (distance − near) · (1 + e + … + e^i) / (1 + e + … + e^(n−1))`.
- Each cascade is a 2048² quarter of the atlas's left half. It is an orthographic view from the sun around the
  bounding sphere of its slice of the view, so its size never changes as the camera turns. Its centre is snapped
  to whole texels, so shadows hold still while the camera moves.
- Each cascade reaches past its split by the transition fraction, and a fragment there blends into the next
  cascade. Shadows fade out over the last tenth of the shadow distance.
- The near plane is pulled back to the farthest caster toward the sun, so a caster outside the view still shadows
  it.
- Each fragment is offset along its normal by one texel of its cascade, and compared one texel nearer.

**Point and spot lights.** The right half of the atlas holds 64 tiles of 512². A spot light takes one tile, a point
light six, one per cube face. Each frame:
- The visible lights marked `CastsShadows` are ranked by range over distance to the eye. The best are given tiles
  while they fit, up to 16 lights. A light keeps its tiles while it stays chosen.
- A light's tiles are redrawn when its light or its casters (their bounds, transforms and meshes) changed, or when a
  skinned model is among its casters. Lights never drawn before go first, then the rest by rank, up to
  `face_budget` (36) faces a frame. A light over budget keeps last frame's tiles.
- The light buffer's last float names each light's shadow, so the clustered loop looks up only the lights that
  have one.
- A face is a perspective view widened by four texels on each side, so filtering never reads past its tile.

**Casters.** `Gather` puts every model in view in `draws`, and every model out of view that can still cast a shadow
into it in `casters`:
- for the sun, when its sphere swept away from the sun reaches the view;
- for a light, when it is within twice the range of the largest shadowed light (last frame's) of the view.

Each cascade and each light face draws only the casters whose bounding spheres reach it, sorted by mesh section
into instanced runs. As Unreal's `r.Shadow.RadiusThreshold` does, a cascade drops a caster whose radius is under a
hundredth of its distance from the eye.

**Filtering.** Every lookup is Castaño's optimized PCF: a 5×5 tent filter from nine bilinear comparisons.

`examples/shadows_check` proves where shadows land. With the sun, boxes 6 m, 32 m and 100 m away (one per cascade)
are seen close and from far above. Each box's shadow behind it is dark, the floor 12 cm past its base is dark, and
its sunny side is as bright as the open floor. A point on a shadow's edge keeps its brightness while the camera
moves. At night, a point light and a spot light each cast a box's shadow onto the floor.

### Post-processing

`SceneVulkan.PostProcess` turns the lit HDR image into the frame with Unreal's post-processing and Unreal's
defaults. Every pass is a full-screen draw or a compute dispatch, timed under its own name in
`renderer.gpu_timings`:

1. **`ambient occlusion`**: ground-truth ambient occlusion (Jimenez et al. 2016) from the depth buffer, with normals
   rebuilt from depth: one slice through each pixel, six steps each way, its angle turned every frame so the next
   pass averages the noise away. It darkens only the sky light: `lit − sky_light × intensity × (1 − visibility)`,
   faded out between `fade_distance − fade_radius` and `fade_distance`.
2. **`temporal aa`**: temporal anti-aliasing (Karis 2014). The projection moves by a sub-pixel jitter each frame
   (Halton 2, 3, eight positions). Each output pixel:
   - rebuilds the new frame from the 3 by 3 render texels around it, each weighted by its distance from the pixel
     after the jitter;
   - finds where it was last frame through the camera's motion, from the closest depth of those texels;
   - reads its history there with a Catmull-Rom filter and clips it to the colour box of the new texels in YCoCg;
   - blends 4% of the new frame in, Unreal's default weight, each side weighted by `1 / (1 + luminance)`.

   An object moving on its own is not reprojected; the colour clip is what keeps it from smearing.
   The output is at the window's size, so a screen percentage below 100 renders the scene smaller and this pass
   upsamples it, as Unreal's temporal upsampling does.
3. **`exposure`**, on a view marked `Scene.Component.AutoExposed`: Unreal's histogram auto exposure. A compute pass
   counts a half-size grid of the frame into 64 bins of EV100 from -10 to 20. A second one averages the bins
   between the low and the high percentile, clamps the average to the minimum and maximum, takes the compensation
   off, and moves the adapted EV100 toward it: at `speed_up` stops a second while the picture brightens and
   `speed_down` while it darkens, linearly while more than 1.5 stops away and exponentially closer. The scene is
   lit with the exposure the GPU adapted two frames before (read back without waiting), and the tone map finishes
   the difference, so the picture changes the frame the exposure does.
4. **`bloom`**: Unreal's Gaussian bloom. Six downsamples (half size to 1/64), each blurred by a separable Gaussian
   whose radius is `size × size_scale` percent of the level's width, halved (sigma half the radius), weighted by its
   tint over six and summed from the coarsest up. Sizes 0.3, 1, 2, 10, 30 and 64; tints 0.3465, 0.138, 0.1176,
   0.066, 0.066 and 0.061. A positive threshold keeps only light brighter than it; -1, the default, blooms
   everything.
5. **`tone map`**: the bloom times its intensity is added, the exposure finished, then Unreal's vignette (the
   cosine-fourth law on a circle whose corners sit at distance 1), the tone curve, the sRGB encoding and a dither.
   The default curve is Unreal's filmic one: the ACES reference transform's glow and red modifier, then a toe, a
   straight section and a shoulder in log space in ACEScg, set by slope, toe, shoulder, black clip and white clip.
   `'aces_fitted'` picks the earlier fit of ACES (Hill) instead.

The settings live on `Scene.Component.View` with Unreal's defaults; each component of the post-processing plugin,
on the entity that carries the lighting, writes its own into every view:

| Component | Fields and defaults |
|---|---|
| `PostProcess.Component.ToneMapper` | `curve` (`'filmic'` or `'aces_fitted'`), `slope` 0.88, `toe` 0.55, `shoulder` 0.26, `black_clip` 0, `white_clip` 0.04 |
| `PostProcess.Component.AutoExposure` | `minimum` -10, `maximum` 20 (EV100), `speed_up` 3, `speed_down` 1, `low_percent` 80, `high_percent` 98.3, `compensation` 1; marks each view `Scene.Component.AutoExposed`, and removing it unmarks them, back to `Lighting.Component.Exposure` |
| `PostProcess.Component.Bloom` | `intensity` 0.675 (0 skips the pass), `threshold` -1, `size_scale` 4 |
| `PostProcess.Component.Vignette` | `intensity` 0.4 |
| `PostProcess.Component.AmbientOcclusion` | `intensity` 0.5 (0 leaves the image alone), `radius` 2 m, `fade_distance` 80 m, `fade_radius` 50 m |
| `PostProcess.Component.ScreenPercentage` | `value` 100: the scene renders at this percentage of the window and is upsampled |

```gdscript
var metering = PostProcess.Component.AutoExposure()
metering.compensation = 0.5
lighting.add_component(metering)
var scaled = PostProcess.Component.ScreenPercentage()
scaled.value = 66.7
lighting.add_component(scaled)
```

Removing a settings component leaves the views at the values it last wrote. `examples/post_check` checks that bloom
spreads light past a bright cube onto a black sky and that none spreads without it, and that auto exposure brings a
floor back to its brightness after the light drops by six stops.

### Masked materials

A material is masked when its Principled BSDF's Alpha is linked; the reader lists its slot in
`Asset.Mesh.masked_materials`. A masked section's texels with alpha below 0.3333 are discarded in every pass, as
Unreal's masked materials clip; every other section is opaque and never discards, whatever its texture's alpha.
Mipmapping averages a cut-out's alpha, so at a distance chain mail and straps read as solid, as they do in Unreal.
Nothing dithers.

**Texture filtering.** Every texture has a full mip chain: a cooked texture brings its own, averaged in linear light
when the recipe compressed it ([assets-and-recipes.md](assets-and-recipes.md#textures-are-cooked-gpu-ready)), and an
uncompressed one gets it on the GPU by blitting each level from the one above. Scene textures sample trilinearly with 16× anisotropic filtering (when the device has it) and repeat
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
- the layer, normal, detail, overlay and far-colour images are `Asset.TextureArray`s (layer-major), which upload one
  layer per frame: a compressed array with the mips it stores (colour arrays as `_SRGB` formats), an RGBA8 one with
  mips made on the GPU. Normals are read from X and Y with Z derived, so a BC5 normal array works as Unreal's does;
- the control, scale, splat and mask images are ordinary `Asset.Texture`s.

A material is drawn once every array and texture has arrived; until then its cells are skipped, so nothing waits.
`examples/terrain_check` cooks a two-by-two-tile fixture and checks that each tile's base layer and a painted splat
land where the formula puts them.

### Grass

Grass is scattered on the GPU around the camera every frame, as Unreal's landscape grass is: nothing is stored per
blade, and a grass type costs the same whether the world is one cell or a thousand. A grass type is an entity with a
`Foliage.Component.GrassType`:

| Field | Means |
|---|---|
| `mesh` | the mesh drawn for each instance, with its sections, textures and masked cut-outs like any model |
| `density` | instances per square metre (Unreal's grass density counts per 10 m by 10 m, a hundred times more) |
| `scale_minimum`, `scale_maximum` | the range of the uniform scale each instance picks |
| `placement_jitter` | how far an instance moves off its grid point, as a fraction of the spacing (1, as in Unreal) |
| `start_cull_distance`, `end_cull_distance` | metres: instances shrink to nothing between the two, as Unreal's do, and none are placed past the end |
| `wind_strength`, `wind_speed` | the sway, in metres per metre of height above the mesh's origin, and its cycles per second |

Two markers shape each instance: `Foliage.Component.AlignToSurface` tilts it to the ground's normal, and
`Foliage.Component.RandomYaw` turns it about its up axis by a random angle. A `Foliage.Component.DensityMap` on the
same entity says where the type grows: a texture spread over the world from the origin, `width` metres along x and
`depth` along z, whose `channel` (0 to 3 for red, green, blue, alpha) scales the density. A type without one grows on
all terrain.

```gdscript
var grass = world.create_entity()
var kind = Foliage.Component.GrassType()
kind.mesh = "grass.meadow"
kind.density = 8.0
kind.end_cull_distance = 90.0
grass.add_component(kind)
var aligned = Foliage.Component.AlignToSurface()
grass.add_component(aligned)
```

Each frame, `Foliage.System.ClearGrass` (`prepare`) empties the `Scene.Grass` resource and `GatherGrass` (`render`)
fills it with every grass type whose mesh has loaded. `SceneVulkan.GrassPass` then:

1. **Captures the ground.** The terrain cells in view are drawn from straight above into a 1024² image of height and
   normal: a square around the camera reaching the farthest end cull distance, snapped to its texels.
2. **Scatters**, with one compute dispatch per type, over a world-space grid whose spacing is `1 / √density`,
   covering the square of the end cull distance around the camera. Each grid cell's jitter, scale, yaw and density
   threshold come from a hash of the cell and the type's entity, so a blade stands in the same place every frame and
   nothing swims as the camera moves. A cell is dropped when it is off the terrain, past the end cull distance,
   thinned out by the density map, or outside the view's four side planes (its sphere, sway included); the rest are
   appended to an instance buffer by an atomic count in each mesh section's indirect draw command.
3. **Draws** each section with one indexed indirect draw, in the scene pass after the terrain, through the scene's own
   fragment shader: grass is lit, receives the sun's shadow and fog, and is cut out like any masked mesh. The vertex
   shader sways each vertex by its height.

Grass casts no shadow. In `examples/foliage_check` (two types, 8 and 1.5 instances per square metre, out to 90 m),
optimized at 1920x1080 on an RTX 3090, the scatter takes 52 µs of GPU time and the grass draw 714 µs.

### Water

A water body is an entity with a `Water.Component.WaterBody` and a `Transform`, whose position is the centre of the
still surface. Its fields follow Unreal's water material:

| Field | Means |
|---|---|
| `extent_x`, `extent_z` | the half size of the body in metres; an ocean is a very large body |
| `albedo_red`, `albedo_green`, `albedo_blue` | the colour of the light the water scatters (Unreal's Water Albedo, 0.85) |
| `scattering` | the scattering coefficient, per metre |
| `absorption_red`, `absorption_green`, `absorption_blue` | the distance in metres over which each colour is absorbed to 1/e (Unreal's Absorption, which it gives in centimetres) |
| `roughness`, `specular` | the surface's roughness (0.02) and specular (0.255, a reflectance of 0.02 straight on) |

Its Gerstner waves are its children: each holds a `Water.Component.GerstnerWave` with `direction_x`, `direction_z`,
`wavelength`, `amplitude` and `steepness`. A wave travels at the deep-water speed of its wavelength, an angular
frequency of `√(9.81 · 2π / wavelength)`, as Unreal's Gerstner waves do; at steepness 1 a lone wave's crest comes to
a point.

```gdscript
var lake = world.create_entity()
lake.add_component(body)
lake.add_component(transform)
var swell = lake.create_entity()
var wave = Water.Component.GerstnerWave()
wave.wavelength = 9.0
wave.amplitude = 0.06
swell.add_component(wave)
```

`Water.System.ClearWater` (`prepare`), `GatherWaterBodies` and `GatherWaves` (`render`) fill the `Scene.Water`
resource. `SceneVulkan.WaterPass` draws after the opaque scene and the grass:

1. It copies the scene's colour, and keeps the depth buffer for testing and for reading.
2. Each body is a grid of 256 by 256 quads made in the vertex shader from the vertex index alone: centred on the
   camera, packed toward it (each side's coordinate squared), reaching the camera's far plane up to 4 km, clamped to
   the body's extent and displaced by the sum of its waves. A wave fades out beyond 40 wavelengths from the eye, so
   the far surface does not shimmer.
3. The fragment shader recomputes the waves' normal for every pixel. The scene depth behind the surface gives the
   thickness of water the view ray crosses; the scene colour behind, bent a little by the normal, is dimmed per colour
   by `exp(-(1 / absorption + scattering) · thickness)`, and the sun and sky light the water scatters back toward the
   eye is added. Shallow water shows the shore through it, and deep water takes the scattered colour. The sky is
   reflected by Schlick's Fresnel and the sun by the scene's GGX highlight, in its shadow; fog comes last.

`examples/foliage_check` puts a lake with four waves into a terrain basin; its pass takes 62 µs at 1920x1080.

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

Lighting data lives on the neutral `Scene.View` with daylight defaults. The lighting plugin only overwrites it from
components, so a scene without that plugin is still lit.

---

Next: [Physics](physics.md), colliders, queries, characters and triggers as components and systems.
