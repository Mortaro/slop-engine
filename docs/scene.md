# 3D: scenes, characters and lighting

Built and tested by `examples/kal_character`: a Kal archer read straight from its `.blend`. It is skinned, textured
and animated, lit by the sun, sky and fog, casts a shadow and is tone mapped, with no Blender install and no
exporter. Everything is split into plugins, so a game loads only what it uses and can replace any piece.

The Kal assets are not in this repository. The example reads them from `D:/Projects/kal-assets`; point it elsewhere
with `spite kal_character --kal_assets=<folder>`.

| Plugin | Namespace | What it brings |
|---|---|---|
| `slop_transform_plugin` | `Transform` | `Transform.Component.Transform`: position, a rotation quaternion and scale |
| `slop_camera_plugin` | `Camera` | `Camera.Component.Camera` (eye, target, field of view, near, far) and `Camera.Component.Orbit` with the `AimOrbit` system |
| `slop_scene_plugin` | `Scene` | `Scene.Component.Model` (a mesh id and a bone palette); `Scene.Component.View` and `Scene.Component.Meshes` on each window; `Gather` collects the camera, the models and the lighting every frame |
| `slop_scene_vulkan_plugin` | `SceneVulkan` | the Vulkan passes: sun shadow map, lit scene into HDR, tone map into the frame, then the UI draws on top |
| `slop_animation_plugin` | `Animation` | `Animation.Component.Animator` (skeleton, clip, time, speed, looping); `Animate` samples the clip into the model's palette |
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
  - Each material's image is its first image-texture node. `MeshReader.images` has the image's name per slot,
    `image_bytes` its packed file, and `image_paths` the file path when the image is not packed (an external
    `.psd`, for example), so the recipe can cook it. The path is Blender's own form, the SDNA field `name`:
    relative to the `.blend` with a leading `//`, and backslashes on Windows. The first image node is taken, not
    the one linked to Base Color, and normal, roughness and metallic maps are not read yet. A hand-built mesh adds a section with
    `mesh.add_section(first, count, texture)` (a proposal by Claude).
  - The renderer draws each section on its own, with its own texture.
- **Skeletons.** Bones are ordered so parents come first. The inverse bind is
  `(to_target · armature_world · arm_mat · to_source)⁻¹`.
- **Actions.** Layered actions (layers, strips, channel bags) and legacy `curves` are both read.
  - Location, quaternion rotation and scale F-curves are evaluated at every whole frame: constant, linear, and
    bezier through a cubic solved for the frame.
  - Each frame is posed in Blender's armature space: `pose[parent] · rest[parent]⁻¹ · rest · basis`.
  - The pose is moved to engine space and stored as the parent-relative position, rotation and scale.

## Animation

`Animate` advances each animator by the tick's fixed step (`Tick().step_milliseconds`) and samples its clip. Measuring
wall-clock time per row made the parts of one character drift apart (the face slid off the head) whenever a tick's
rows crossed a millisecond; the fixed step keeps every part of a character in lockstep and makes captures repeatable.
- Position and scale are interpolated linearly.
- Rotation uses a shortest-arc slerp, falling back to a normalised lerp for near-identical keys.
- It writes `global · inverse_bind` for each bone into `Scene.Component.Model.palette`, and each bone's model-space
  pose (`global`) into `Model.bones`.

### Bone attachments

A weapon, a shield or an effect rides a bone of another entity's animated skeleton (proposal by Claude, for Mortaro
to decide). Give it a `Transform`, an `Animation.Component.BoneAttachment`, and make it a child of the carrier:

```gdscript
var sword = world.create_entity()
var attachment = Animation.Component.BoneAttachment()
attachment.bone = "Bip01 R Hand"
attachment.rotation_z = 0.7071068
attachment.rotation_w = 0.7071068
sword.add_component(attachment)
sword.add_component(model)
sword.add_component(transform)
sword.add_parent_entity(carrier)
```

How it's resolved:
- **Placement:** each frame, `FollowBones` (`prepare`, after `Animate`, before the scene is gathered) writes the
  attachment's `Transform` in world space: the carrier's `Transform`, times the bone's pose, times the attachment's
  offset (position, rotation, scale in the bone's space).
- **Which bone:** name the bone with `bone`, or give `bone_index` (0 or more) for an index, as monsters' effect bones
  are. The name is looked up once in the carrier's skeleton and cached against the name, so changing `bone` later
  looks it up again. A name the skeleton doesn't have crashes, naming the bone and the skeleton.
- **The carrier:** it needs an `Animator`, a `Model` and a `Transform`. Until its skeleton has loaded and been posed,
  the attachment keeps its own `Transform`.
- **Despawning:** because the attachment is a child, it despawns with its carrier.

`examples/attachment_check` checks a named bone with an offset and an indexed bone on a synthetic, turned skeleton.

The scene plugin knows nothing of animation: it uploads any palette a model carries, and the vertex shader skins
with four bones per vertex.

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

Cut-out texels (alpha below 0.5) are discarded in every pass.

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
1. `ClearLights` (`prepare`) empties the `Scene.Lights` singleton.
2. `GatherPointLights` and `GatherSpotLights` (`render`) stream every light into it, 16 floats each.

Only the position is read, so a light that is a child of a moving entity needs its own transform kept in world
space (proposal: follow the parent once transforms have a world pass).

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
- gathering costs 0.9 to 1.1 ms. That is the ECS's per-row cost of streaming a two-component row (about 300 ns), not
  the lights, so it drops wherever that cost does (docs/performance.md).

Not built yet:
- shadows for point and spot lights (a budgeted atlas, a proposal);
- tighter sphere-against-cluster tests, which only cost shading a light that adds zero;
- moving the cluster pass to a compute shader, if the CPU cost matters once many lights are on screen.

Lighting data lives on the neutral `Scene.View` with daylight defaults. The lighting plugin only overwrites it from
components, so a scene without that plugin is still lit.

## Not built yet

These are what the previous Kal renderer had:
- the ray-marched atmosphere and sky;
- shadow cascades and contact shadows;
- GTAO;
- image-based sky lighting;
- bloom;
- 4× MSAA;
- automatic exposure from a histogram;
- mipmaps and anisotropic filtering for scene textures;
- Blender's custom split normals (`custom_normal` is ignored and normals are recomputed);
- blending between clips.
