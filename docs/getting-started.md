# Getting started

## What you need

- Windows, and the Spite compiler at `D:\Projects\SpiteLanguage` (`bin/spite`, which builds itself from its seed on
  first use with the C compiler it finds).
- A Vulkan 1.3 driver for the Vulkan backend. The validation layer is used when it is installed and the build is not
  `--optimized`; its absence is not an error.
- The Vulkan SDK's `glslangValidator`, found through `VULKAN_SDK`, is the one tool still needed: the shader recipe
  calls it. Everything else, including reading `.psd`, zstd and `.blend` files, is Spite code.

## Run the examples

From `examples/`, where `spite` means `D:/Projects/SpiteLanguage/bin/spite`:

```bash
spite click_counter                          # a Vulkan window with a textured button that counts clicks
spite click_counter_test                     # the game, loaded by its test: hidden window, 5 real clicks
spite click_counter_test -- --clicks=12 --show_window=true
spite scroll_list                            # a scrolling list of clickable rows
spite scroll_list_test                       # scrolls it with the wheel and clicks a row, in a hidden window
spite text_field                             # a form with one text field
spite text_field_test                        # clicks and types into it in a hidden window
spite hot_reload_test --debug-memory          # change a source while running; the texture updates in both renderers
spite flex_layout --debug-memory             # 91 layout checks: flexbox, grid, scrolling, clipping, z-index
spite render_parity --debug-memory           # Vulkan against the software rasteriser, every pixel
spite tracking --debug-memory                # Added and Removed, each seen exactly once
spite use_potion --debug-memory              # two related query rows
spite healing --debug-memory                 # headless systems, a parallel stage
spite stress --optimized                     # 200,000 entities, timings
```

`--debug-memory` prints the program's allocation balance at the end; every example above ends balanced. Arguments
after `--` are the program's own `Environment` settings. Arguments before it that aren't the compiler's are `Build`
fields, decided at compile time.

## A program

A Spite program is a folder, and its entry is the file named like the folder. A SlopEngine program's entry loads the
core and the plugins it wants, runs its recipes, makes the app, and runs:

```gdscript
# examples/click_counter/click_counter.spite
var cookbook = Recipes.Cookbook()

func ClickCounter() {
    load "../../slop"
    load "../../plugins/slop_window_plugin"
    load "../../plugins/slop_platform_plugin"
    load "../../plugins/slop_input_plugin"
    load "../../plugins/slop_ui_plugin"
    load "../../plugins/slop_render_plugin"
    load "../../plugins/slop_render_vulkan_plugin"
    load "../click_counter_theme_plugin"
    cookbook.cook()
    var app = App()
    app.run()
}
```

The entry loads and runs, and nothing else: it spawns nothing. The world's first entities come from systems whose
rows say when, like everything else. `System.OpenMainWindow` asks for `Added<Component.Frame>`, which matches once, in
the first tick, because `App()` puts the frame counter on the world entity; `System.SpawnCounter` asks for
`Added<Window.Component.Window>` and builds the UI tree.

Nothing is registered. `App()` finds every system by folder; `cookbook.cook()` finds every recipe by folder. Loading a
plugin's folder is how a game opts into it: load `render_software` instead of `render_vulkan` and the same game draws
on the CPU.

The game's own code sits in the same folder conventions as every plugin (see [conventions.md](conventions.md)):

```
examples/click_counter/
  click_counter.spite           the entry
  component/                    ClickCount, ButtonPrimary
  bundle/                       CounterButton, Title
  system/                       OpenMainWindow, SpawnCounter, CountClicks
examples/click_counter_theme_plugin/theme/
  assets/ui/buttons.psd         the artist's file, asset id ui.buttons
  recipe/ui.spite               cuts the button plates out of it
  system/                       dresses primary buttons, and the four hover and press styles
```

## Paths

A program runs in the folder `spite` was called from. The engine resolves its own files from `Build().program` (the
entry folder, absolute) joined with `Build().slop_folder` (`../../slop`) or `Build().plugins_folder`
(`../../plugins`), which mirror the `load(...)` literals. Asset sources are found by id and cooked assets live
in one cache binary; see [assets-and-recipes.md](assets-and-recipes.md).

---

Next: [The ECS](ecs.md), entities, components and the systems that query them.
