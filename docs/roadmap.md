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
| 1 | ECS throughput | despawn and spawn in bulk within a frame budget (200,000 despawns take 224 ms today), parallel iteration inside one system |
| 2 | PSD | ZIP-compressed channels (a re-saved file can crash a build today), alpha, 16-bit, then PSB |
| 3 | Headless server | a fixed-rate tick, timers as components, one spatial grid for replication, sight and aggro; 5,000 players and 10,000 monsters |
| 4 | Networking | area of interest, removal replication, handshake with a version, delta compression, frames over 64 KiB, rate limits, reconnect |
| 5 | MongoDB | SCRAM-SHA-256 and indexes; TLS later |
| 6 | Navigation | a walkability bitgrid cooked from terrain and collision, grid A*, line of sight |
| 7 | Collision | heightfield, capsule and static mesh colliders, raycasts, a character controller, the same on the server |
| 8 | Profiling | CPU time per system and stage, dumped to JSON: built first, since the first server comparison needs it ([performance.md](performance.md#measuring-the-profile)); GPU timestamps per pass still to do |
| 9 | `.blend` | ear-clipping triangulation, custom normals, several UV sets, vertex colours, several materials, LODs, `UCX_` collision, external `.psd` images |
| 10 | Textures | BC1/3/4/5/7 cooked offline, mips, anisotropic filtering, raw bytes, mip streaming |
| 11 | Client | GPU-driven renderer, world streaming, terrain, foliage, materials, lighting, hierarchy and sockets, animation blending, UI, audio, particles |

Waiting on the language: resizing, fullscreen and IME need callbacks from C. Value columns for components that hold
lists or references need the language to lay such classes out inline.
