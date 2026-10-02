# Roadmap

What SlopEngine builds next, and why in this order. The order is a proposal by Claude; Mortaro decides it and the
API of each piece.

## The first game's request

A game built on the engine, an MMO moving from Unreal 5.8 and C# onto SlopEngine, asked for the list below on
2026-09-26. The full request is section 5 of that game's plan. The bar is to beat the packaged Unreal build, so every item
ships with a number measured against Unreal's number for the same scene. The server is ported first, so the server
items come first.

| Order | Item | What it means |
|---|---|---|
| 1 | ECS throughput | despawn and spawn in bulk within a frame budget (200,000 despawns: 224 ms, now 22 ms), parallel iteration inside one system: automatic, with no opt-in (Mortaro, 2026-09-26: whatever performs best, as long as game code does not change); waits on a folded race check from the language |
| 2 | PSD | ZIP and ZIP-with-prediction channels, alpha and 16-bit are built; PSB and a faster decode remain |
| 3 | Headless server | built: a fixed-rate tick, timers as components, one spatial grid for replication, sight and aggro. `server_bench` ticks 5,000 players and 10,000 monsters in about 8.5 ms (2026-09-26) |
| 4 | Networking | area of interest, removal replication, replication by write (`Changed<T>`), a handshake refusing mismatched builds, unreliable datagrams and a server-owned clock are built; frames over 64 KiB, rate limits, prediction, reconnect and a per-peer change list remain |
| 5 | MongoDB | SCRAM-SHA-256 and indexes; TLS later |
| 6 | Navigation | built (2026-10-02): a walkability grid baked from triangles (meshes and heightfields) in a recipe, grid A*, line of sight, smoothing and bots following paths ([navigation.md](../docs/navigation.md)); water and safe planes and reading collision from `.blend` remain ([status.md](status.md#navigationmd)) |
| 7 | Physics | fully ECS (colliders, bodies and contacts are components, stepping is systems), so it runs in parallel with everything else instead of on one locked thread as in Unreal; box, sphere, capsule and static mesh colliders, a grid broad phase, raycasts and sweeps, a character controller and triggers are built ([physics.md](../docs/physics.md)); a heightfield collider, collision layers and rigid bodies remain. The same 3D physics on server and client, replacing the C# server's 2D, if it keeps thousands of players within the tick budget: one simulation means the server can check movement the way the client moves, which closes many cheats |
| 8 | Profiling | CPU time per system and stage, dumped to JSON: built first, since the first server comparison needs it ([performance.md](../docs/performance.md#measuring-the-profile)); GPU timestamps per pass still to do |
| 9 | `.blend` | ear-clipping triangulation, custom normals, several UV sets, vertex colours, LODs, `UCX_` collision, cooking external `.psd` images; several materials per mesh is built |
| 10 | Textures | BC1/3/4/5/7 cooked offline, mips, anisotropic filtering, raw bytes, mip streaming |
| 11 | Client | GPU-driven renderer, world streaming, terrain, foliage, materials, lighting, hierarchy and sockets, animation blending, UI, audio, particles |

### Mortaro's decisions (2026-09-26)

Recorded in full in section 8 of the game's plan.

- **Visuals match what Unreal renders for the game today**, not only its frame rate: Lumen GI and reflections,
  virtual shadow maps, mesh distance fields, hardware ray tracing, Substrate, Nanite on dungeon meshes, and DLSS 4
  at 66.7% screen percentage, so an upscaler is part of the comparison. Lighting starts by porting the old engine's
  shaders (ambient occlusion, anti-aliasing, BRDF, bloom, clustered lights, exposure, fog, image-based lighting,
  shadows, TAA, terrain, tone mapping, sky, environment capture and prefilter), and it ranks beside the renderer.
  Those shaders do not cover Lumen, virtual shadow maps, ray tracing or Nanite; each of those is its own project.
- **Networking is component replication** serialised with `BinaryWriter`/`BinaryReader`, the fastest wire
  possible, with no hand-written packets. The C# server's 81 requests and 117 responses become replicated components
  and request components sent by the client.
- **All UI is SlopEngine UI built from PSDs**: about 81 widgets, 2,054 item icons, 260 skill icons and 58 buff icons.
  UI needs real fonts, slot grids with drag and drop, draggable windows, tooltips, a scrolling chat log, a minimap
  render target, nameplates and floating damage numbers. PSD robustness matters for every screen.
- **Windows only** for now; Linux later.
- **Physics** (2026-09-27): completely ECS, a source of easy wins over Unreal's main-thread physics; and 3D on the
  server as well as the client (the C# server is 2D) if SlopEngine beats the C# server's performance with thousands
  of players, since a server running the client's physics can reject impossible movement.
- **Audio drops to P2** (the Unreal client plays none). **Particles** are CPU sprites read from `particles.json`, plus
  beams, ribbons and projectiles. **Terrain** is splat-index shading, control maps over a 78-slice texture array,
  so textures and terrain need texture arrays.

- **Blender is the editor** (the game's decision D18): each map is one `.blend` whose objects are linked from an object-library
  `.blend`; NPCs, spawn areas, portals, safe zones and water are objects or empties with custom properties. Recipes
  read it and cook everything else. The engine needs the Blend readers to follow library links and collection
  instances and to read custom properties (IDProperties), a navigation bake recipe (0.8 m walkability grid with
  water and safe planes), and a continent cooked into streaming chunks loaded on the pool as the camera moves.
- **Particles** are a new binary asset (`Asset.ParticleSystem`: emitters, rates and bursts, lifetimes, forces,
  curves over life, textures or flipbooks, blend modes, sprites, meshes, ribbons and beams) cooked from a recipe
  source, simulated and drawn on the GPU (compute update, indirect draw), played by a component such as
  `Particles.Component.Emitter`. The old C++ particle design is not to be copied.

### Source material from the game

Everything is in the game's repository:

- **Material graphs** (for materials and lighting): `export/material_graphs/**/*.t3d`, 132 Unreal master materials
  as T3D text, with every expression, connection and custom HLSL. The key one is
  `Maps/World/World_Terrain/M_Terrain.t3d`: splat-index shading from absolute world UVs, with control maps
  (`T_ctrlIdxA/B`, `T_ctrlSclA/B`, `T_TSplat0/1`) indexing a 78-slice texture array, plus `T_Detail` and a baked
  `T_TerrainAlbedo`, all as PSDs in `assets/textures/Maps/World/World_Terrain/`.
- **Terrain**: `assets/maps/<map>/terrain/cell_X_Y.blend`, 256×256 quads at 320 cm (819.2 m cells), 174 cells over
  12 maps, the World 83 dry cells. UV0 spans the whole map. Raw uint16 heightfields are in
  `export/landscape/*` (one landscape file per map): world Z = SourceZ + (h − 32768) · scale_z / 128.
- **Lights**: dungeons hold thousands of dynamic point and spot lights (RoyalTomb 3,053), so clustered lighting is
  required. Built (A47): `PointLight` and `SpotLight`, clustered forward shading, unshadowed ([scene.md](../docs/scene.md)). Scenes are Spite records in `data/scene/<map>.spite`.
- **Scale**: the World places 17,357 objects, dungeons 1,000 to 4,000, all as separate actors in Unreal with no
  instancing, so instancing identical meshes is where SlopEngine gains.
- **Characters**: `assets/characters/<class>/<class>.blend` (rig, body, actions) and `sets/set_N.blend` (one
  armour set each, with its own copy of the rig).

Waiting on the language: resizing, fullscreen and IME need callbacks from C. Value columns for components that hold
lists or references need the language to lay such classes out inline.
