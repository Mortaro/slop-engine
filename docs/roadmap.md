# Roadmap

What SlopEngine builds next, and why in this order. The order is a proposal by Claude; Mortaro decides it and the
API of each piece.

## Theseus

Theseus, an MMO moving from Unreal 5.8 and C# onto SlopEngine, asked for the list below on 2026-09-26. The full
request is `D:/Projects/SlopTheseus/PLAN.md`, section 5. The bar is to beat the packaged Unreal build, so every item
ships with a number measured against Unreal's number for the same scene. The server is ported first, so the server
items come first.

| Order | Item | What it means |
|---|---|---|
| 1 | ECS throughput | despawn and spawn in bulk within a frame budget (200,000 despawns: 224 ms, now 22 ms), parallel iteration inside one system: automatic, with no opt-in (Mortaro, 2026-09-26: whatever performs best, as long as game code does not change); waits on a folded race check from the language |
| 2 | PSD | ZIP and ZIP-with-prediction channels, alpha and 16-bit are built; PSB and a faster decode remain |
| 3 | Headless server | built: a fixed-rate tick, timers as components, one spatial grid for replication, sight and aggro. `server_bench` ticks 5,000 players and 10,000 monsters in about 8.5 ms (2026-09-26) |
| 4 | Networking | area of interest, removal replication, handshake with a version, delta compression, frames over 64 KiB, rate limits, reconnect |
| 5 | MongoDB | SCRAM-SHA-256 and indexes; TLS later |
| 6 | Navigation | a walkability bitgrid cooked from terrain and collision, grid A*, line of sight |
| 7 | Collision | heightfield, capsule and static mesh colliders, raycasts, a character controller, the same on the server |
| 8 | Profiling | CPU time per system and stage, dumped to JSON: built first, since the first server comparison needs it ([performance.md](performance.md#measuring-the-profile)); GPU timestamps per pass still to do |
| 9 | `.blend` | ear-clipping triangulation, custom normals, several UV sets, vertex colours, LODs, `UCX_` collision, cooking external `.psd` images; several materials per mesh is built |
| 10 | Textures | BC1/3/4/5/7 cooked offline, mips, anisotropic filtering, raw bytes, mip streaming |
| 11 | Client | GPU-driven renderer, world streaming, terrain, foliage, materials, lighting, hierarchy and sockets, animation blending, UI, audio, particles |

### Mortaro's decisions (2026-09-26)

Recorded in full in `D:/Projects/SlopTheseus/PLAN.md`, section 8.

- **Visuals match what Unreal renders for Theseus today**, not only its frame rate: Lumen GI and reflections,
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
- **Audio drops to P2** (the Unreal client plays none). **Particles** are CPU sprites read from `particles.json`, plus
  beams, ribbons and projectiles. **Terrain** is splat-index shading, control maps over a 78-slice texture array,
  so textures and terrain need texture arrays.

### Source material from Theseus

Everything is under `D:/Projects/SlopTheseus`:

- **Material graphs** (for materials and lighting): `export/material_graphs/**/*.t3d`, 132 Unreal master materials
  as T3D text, with every expression, connection and custom HLSL. The key one is
  `Maps/World/World_Terrain/M_Terrain.t3d`: splat-index shading from absolute world UVs, with control maps
  (`T_ctrlIdxA/B`, `T_ctrlSclA/B`, `T_TSplat0/1`) indexing a 78-slice texture array, plus `T_Detail` and a baked
  `T_TerrainAlbedo`, all as PSDs in `assets/textures/Maps/World/World_Terrain/`.
- **Terrain**: `assets/maps/<map>/terrain/cell_X_Y.blend`, 256×256 quads at 320 cm (819.2 m cells), 174 cells over
  12 maps, the World 83 dry cells. UV0 spans the whole map. Raw uint16 heightfields are in
  `export/landscape/*.theseusland`: world Z = SourceZ + (h − 32768) · scale_z / 128.
- **Lights**: dungeons hold thousands of dynamic point and spot lights (RoyalTomb 3,053), so clustered lighting is
  required. Scenes are Spite records in `data/scene/<map>.spite`.
- **Scale**: the World places 17,357 objects, dungeons 1,000 to 4,000, all as separate actors in Unreal with no
  instancing, so instancing identical meshes is where SlopEngine gains.
- **Characters**: `assets/characters/<class>/<class>.blend` (rig, body, actions) and `sets/set_N.blend` (one
  armour set each, with its own copy of the rig).

Waiting on the language: resizing, fullscreen and IME need callbacks from C. Value columns for components that hold
lists or references need the language to lay such classes out inline.
