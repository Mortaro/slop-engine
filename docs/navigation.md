# Navigation

`slop_navigation_plugin` moves bots over the ground without a client: a recipe bakes where an agent can stand into
a grid asset, A* finds paths on it, and systems walk entities along them. It is headless, so a server and its bots
load it as they are. `cookbook.cook_recipes()` runs every recipe once without watching their sources for hot
reload, which a server has no use for.

```gdscript
var cookbook = Recipes.Cookbook()

func Server() {
    load "../../slop"
    load "../../plugins/slop_navigation_plugin"
    cookbook.cook_recipes()
    var cooked = Navigation.Cooked()
    var map = Navigation.Map()
    map.use(cooked.walkability("navigation.world"))
    var app = App()
    app.run()
}
```

## The walkability grid

The world is cut into square cells seen from above, 0.8 m by default. A cell is walkable when an agent can stand in
it: some ground under it slopes no more than the slope limit, nothing within the agent's height above that ground
blocks it, and no neighbouring cell's ground is a drop the agent could not step down. The grid keeps one bit per
cell, and the height of the ground an agent stands on there.

`Navigation.Asset.Walkability` is the cooked form, an asset class like any other
([assets-and-recipes.md](assets-and-recipes.md#assets-are-declared-classes)):

| Attribute | Holds |
|---|---|
| `columns`, `rows` | the grid's size in cells |
| `cell_size` | metres per cell |
| `origin_x`, `origin_z` | the world position of the corner of cell 0 |
| `walkable` | one bit per cell, 32 cells to an `Integer`, row by row |
| `heights` | the standing height of each cell (0 where it is not walkable) |

`cover(columns, rows)`, `mark_walkable(cell, height)`, `is_walkable(cell)` and `walkable_count()` build and read one
by hand, which is how a test makes a grid without geometry.

## Baking from triangles

`Navigation.Bake` is a recipe step: a recipe feeds it the world's triangles and puts what it bakes into the cache.

```gdscript
# examples/navigation_check/recipe/walkability.spite
var cache = Recipes.Cache()

func build() {
    var fingerprint = cache.fingerprint("navigation check course 1")
    assert not cache.is_current("navigation.check.course", fingerprint)
    var course = Course()
    var walkability = course.build()
    var pack = Pack<Navigation.Asset.Walkability>()
    var bytes = Asset.Bytes()
    pack.encode(walkability, bytes)
    cache.put("navigation.check.course", fingerprint, bytes)
}
```

| Call or setting | Does |
|---|---|
| `cell_size` (0.8), `agent_height` (1.8), `maximum_slope_degrees` (45), `step_height` (0.5) | the agent; set them before `cover` |
| `cover(left, top, columns, rows)` | the area to bake: the corner at (`left`, `top`) on the ground plane and the size in cells |
| `add_triangle(...)` | one triangle, nine coordinates; its front is the side its corners turn counter-clockwise around, as in every engine mesh |
| `add_mesh(mesh, transform)` | every triangle of an `Asset.Mesh`, placed by a `Transform.Component.Transform` |
| `add_heightfield(samples, columns, rows, spacing, left, base, top)` | a terrain: `samples` heights row by row, `spacing` metres apart, added to `base`, with sample 0 at (`left`, `top`) |
| `finish()` | the `Navigation.Asset.Walkability` |

Each triangle is clipped against every cell it covers, and what lies inside a cell becomes a span: the lowest and
highest point of the triangle in that cell, and whether the triangle faces up within the slope limit. Spans that
touch in a cell merge, the way Recast builds its heightfield; a wall's span reaches over the ground it stands on, so
the ground there is not walkable. A cell's floor is the top of its highest walkable span with at least
`agent_height` of room above it. Last, a floor is dropped when a neighbour's floor lies lower by more than
`step_height`, or than the slope limit allows across one cell, so a ledge never joins the ground below it.

Geometry is read as surfaces, as Recast reads it: the inside of a closed box taller than the agent has a floor, but
its walls cut it off, so no path reaches it (see [regions](#regions)).

`Navigation.Cooked().walkability(id)` reads a cooked grid back from the cache, and `Navigation.Map().use(walkability)`
makes it the grid every navigation system uses. Both read files or build tables, so a program calls them while it
starts, never from a system.

## Paths

`Navigation.Grid` is the grid in memory, made by `use(walkability)`, one byte per cell. `Navigation.Map` holds the
program's grid as `map.grid`.

| Call | Answers |
|---|---|
| `column_of(x)`, `row_of(z)`, `center_x(column)`, `center_z(row)` | from world positions to cells and back |
| `open(column, row)`, `open_cell(cell)` | whether a cell is walkable (outside the grid is not) |
| `height_of(cell)` | the standing height |
| `nearest_open(column, row, reach)` | the closest walkable cell within `reach` cells, or -1 |
| `line_of_sight(from_cell, to_cell)` | whether the straight line between two cell centres crosses only walkable cells |
| `connected(first, second)` | whether a path can exist between two cells |

`Navigation.Search` finds paths. It keeps scratch tables the size of the grid and reuses them, so a program keeps
one and asks it again:

| Call | Does |
|---|---|
| `search.find(grid, start, goal)` | A* from cell to cell; answers whether a path exists, and fills `cells` (start to goal), `cost` (in cells, a diagonal step costing 1.414) and `expanded` |
| `search.smooth(grid)` | string pulling: fills `smoothed` with the cells of `cells` where the path must turn, keeping each straight stretch in line of sight |

The search moves to the eight neighbours of a cell, never cutting the corner of a cell that is not walkable, and is
guided by the octile distance, which never overestimates, so the path it finds is a shortest one.
`examples/navigation_check` checks every cost against a brute-force Dijkstra on random grids.

Line of sight walks every cell the line touches, and where the line passes exactly through a corner it asks for both
cells beside it, the same rule the search follows, so a smoothed path crosses nothing the search would not.

### Regions

`use` labels every group of walkable cells that reach each other, so `find` answers a goal no path reaches at once,
without flooding the whole region first. An island (a plateau ringed by steep slopes, the inside of a closed box)
is a region of its own.

## Bots that follow paths

A bot is an entity with a `Transform.Component.Transform`. It asks for a path by having a destination, and the
plugin's systems answer and walk it:

| Component | Holds | Means |
|---|---|---|
| `Navigation.Component.Destination` | `position_x`, `position_z` | where the bot wants to go; adding it asks for a path |
| `Navigation.Component.Speed` | `meters_per_second` (4) | how fast it walks; a bot without one gets its path but stays |
| `Navigation.Component.Searching` | marker | its path was asked for and is not landed yet |
| `Navigation.Component.Heading` | link | the waypoint it walks toward |
| `Navigation.Component.Waypoint` | `position_x`, `position_z` | on a waypoint entity, a child of the bot |
| `Navigation.Component.Next` | link | on a waypoint: the one after it; the last has none |
| `Navigation.Component.Arrived` | marker | the bot reached its destination |
| `Navigation.Component.Unreachable` | marker | no path leads to its destination |

A path is a list, and a component holds no list, so a path is entities: each corner of the smoothed path is a
waypoint entity, a child of the bot (so it goes when the bot does), linked to the next by `Next`, and the bot links
to the one it walks toward with `Heading`. Walking is following a link, which is what a two-row system does
([ecs.md](ecs.md#following-a-link)).

| System | Does |
|---|---|
| `Navigation.System.RequestPaths` (`update`) | on `Added<Destination>`: clears the bot's old path, `Arrived` and `Unreachable`, adds `Searching`, and answers the requests of the tick as one `Navigation.SearchJob`, whose answers wait in the `Navigation.Searches` resource |
| `Navigation.System.LandPaths` (`input`) | takes finished batches, up to 512 bots a tick so a burst of answers is spread over ticks: spawns each bot's waypoints and adds `Heading`, or adds `Unreachable`, and removes `Searching`; a result for a destination that has changed since is dropped |
| `Navigation.System.FollowPaths` (`update`) | moves each bot toward its `Heading` waypoint by its speed times the tick's step, stands it on the grid's height, and on reaching the waypoint heads for the `Next` one, or removes `Heading` and adds `Arrived` |
| `Navigation.System.CancelPaths` (`update`) | on `Removed<Destination>` (and no new one): despawns the path and removes `Heading`, `Arrived` and `Unreachable` |

A search starts at the walkable cell nearest the bot and ends at the one nearest the destination (within four
cells); the last waypoint is the destination itself when it lies in a walkable cell. The searches share one
`Navigation.Search` (`Navigation.Searchers`) and read the grid, which nothing writes while the app runs. The answers
land in `LandPaths` on the next tick, and the bot has `Searching` meanwhile.

Replacing a `Destination` that is already there changes its values in place, which `Added` does not see. To send
a bot somewhere new, remove its `Destination` and add the new one in the same tick: the old path goes and the new
search starts.

`examples/navigation_check` bakes a course from a heightfield, ramps, ceilings and a wall mesh, checks which cells
are walkable, and walks a bot around the wall until it has `Arrived`, while a second bot asking for an island
gets `Unreachable`.

---

Next: [Performance](performance.md), measuring a build and keeping frames free of stutters.
