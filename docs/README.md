# SlopEngine documentation

SlopEngine is an ECS game engine written in the Spite language: Bevy, with Spite's compile-time metaprogramming in
place of Bevy's type machinery. These pages describe what is built today. Every example they name runs, and every
claim about behaviour is checked by one of the programs in `examples/` (see [testing.md](testing.md)).

| Page | What it covers |
|---|---|
| [getting-started.md](getting-started.md) | installing nothing, running the examples, the shape of a program |
| [ecs.md](ecs.md) | entities, components, markers, state as components, systems, rows, relations, change tracking, phases, threads |
| [plugins.md](plugins.md) | every plugin: what it brings, its components and systems |
| [ui.md](ui.md) | buttons, interaction markers, styles as components, how a game writes state styles |
| [rendering.md](rendering.md) | the draw list, the software and Vulkan backends, parity, the window without callbacks |
| [assets-and-recipes.md](assets-and-recipes.md) | asset formats as declared classes, recipes as code, the cache, background loading |
| [networking.md](networking.md) | environments as folders (client, server, bot), replicated components, the binary wire (proposal, built) |
| [loaders.md](loaders.md) | PSD, zstd and `.blend` read in pure Spite |
| [testing.md](testing.md) | every example, what it proves, and how to run it |
| [performance.md](performance.md) | the stress numbers, where the time goes, what would make it faster |
| [conventions.md](conventions.md) | folders, naming, and the rules the engine enforces |

What Spite itself still lacks, and every bug found while building this, is in [../INSIGHTS.md](../INSIGHTS.md). The
decisions behind the design are Mortaro's; where a page says "proposal", it is Claude's and unconfirmed.
