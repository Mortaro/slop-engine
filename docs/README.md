# SlopEngine documentation

SlopEngine is an ECS game engine written in the Spite language: Bevy, with Spite's compile-time metaprogramming in
place of Bevy's type machinery. These pages describe how to build a game with it. Every example they name runs, and
every claim about behaviour is checked by one of the programs in `examples/` (see [testing.md](testing.md)).

## Reading order

Read the pages in this order the first time; each page assumes the ones before it and ends with a link to the next.

1. [getting-started.md](getting-started.md): what you need, running the examples, the shape of a program.
2. [ecs.md](ecs.md): entities, components, markers, links between entities, systems and rows, change tracking,
   phases, timers, storage and IO systems.
3. [conventions.md](conventions.md): folders, naming, and the rules the engine enforces.
4. [plugins.md](plugins.md): every plugin, what it brings, its components and systems.
5. [ui.md](ui.md): elements as entities, layout as one component per CSS property, scrolling, text input, drag and
   drop, styles as components, fonts.
6. [rendering.md](rendering.md): the draw list, the software and Vulkan backends, parity, the window.
7. [assets-and-recipes.md](assets-and-recipes.md): asset formats as declared classes, recipes as code, the cache,
   worktrees, hot reload, background loading.
8. [loaders.md](loaders.md): PSD, zstd and `.blend` read in pure Spite.
9. [scene.md](scene.md): 3D: characters cooked from `.blend`, animation, bone attachments, lighting, terrain, point
   and spot lights.
10. [networking.md](networking.md): environments as folders (client, server, bot), replicated components,
    observers and area of interest, the binary wire.
11. [performance.md](performance.md): measuring, the profile, where the time goes, how the engine avoids stutters.
12. [testing.md](testing.md): every example, what it proves, and how to write a test.
