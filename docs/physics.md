# Physics

Colliders, queries, a character controller and trigger volumes, all in the ECS: a collider is a component on an
entity, an overlap with a trigger is an entity, and the work is done by systems, so physics shares stages with
every system that does not touch it. The same plugin runs on a server and on a client, so a server can move a
player exactly the way the player's client does. `examples/physics_check` tests every piece below and
`examples/physics_bench` measures it ([testing.md](testing.md)).

A program loads it with one line, which also loads `slop_transform_plugin`:

```gdscript
load "../../plugins/slop_physics_plugin"
```

## Colliders are components

An entity with a `Transform.Component.Transform` and one shape component is a collider. The shape is centred on the
transform's position and turned by its rotation; a primitive's size is its component's, and the transform's scale
applies only to a mesh.

| Component | Holds | Means |
|---|---|---|
| `Physics.Component.BoxCollider` | `half_x`, `half_y`, `half_z` | a box, half its size along each of its own axes |
| `Physics.Component.SphereCollider` | `radius` | a sphere |
| `Physics.Component.CapsuleCollider` | `radius`, `half_height` | a capsule along its own y axis: a segment `half_height` each way from the centre, grown by `radius` |
| `Physics.Component.MeshCollider` | `mesh` | the triangles of the mesh of that name in `Physics.Meshes`; always static |
| `Physics.Component.Kinematic` | marker | the collider is moved by code: it is read again every tick |
| `Physics.Component.Trigger` | marker | the collider is a trigger volume: it reports what enters and leaves it and blocks nothing ([below](#triggers)) |

A collider without `Kinematic` is static: it is read when its shape component is added, and adding the component
again (with new values, or after moving the transform) reads it again. Removing the shape component, or despawning
the entity, takes the collider out. Whether a collider is a trigger, and whether it is kinematic, is read when its
shape is added, so the markers go on with the shape, in the same flush. An entity has one shape; a compound shape
is several entities.

```gdscript
var wall = world.create_entity()
var transform = Transform.Component.Transform()
transform.position_x = 10.0
transform.position_y = 1.5
wall.add_component(transform)
var box = Physics.Component.BoxCollider()
box.half_x = 0.5
box.half_y = 1.5
box.half_z = 6.0
wall.add_component(box)
```

### Meshes are asset data

A mesh's triangles are asset data held by an object, never a list in a component. `Physics.Meshes` is a resource
holding each `Physics.TriangleMesh` by name, and a `MeshCollider` names one:

```gdscript
var meshes = Physics.Meshes()

func build_ramp() {
    var ramp = Physics.TriangleMesh()
    var low_left = ramp.add_vertex(0.0, 0.0, 0.0)
    var low_right = ramp.add_vertex(0.0, 0.0, 4.0)
    var high_left = ramp.add_vertex(6.0, 2.0, 0.0)
    var high_right = ramp.add_vertex(6.0, 2.0, 4.0)
    ramp.add_triangle(low_left, low_right, high_left)
    ramp.add_triangle(high_left, low_right, high_right)
    meshes.add("ramp", ramp)
}
```

The mesh is added before the collider that names it; a `MeshCollider` naming a mesh that is not there crashes when
it is indexed. Indexing turns each triangle into its own entry in the broad phase, placed by the entity's whole
transform, scale included.

## The broad phase

`Physics.Colliders` is the resource that indexes every collider. It keeps each shape in world space in flat lists
(one entry per primitive or triangle), its bounds, and two grids over the ground plane: one of static colliders and
one of kinematic ones, plus a third of characters, used only by triggers. A grid is a spatial hash of cells (4 m by
default; `colliders.configure(cell_size)` changes it): an entry is listed in every cell its bounds cover, sorted by
cell in one counting pass, so a query reads a few short runs of entries. An entry covering more than 256 cells (a
floor, a terrain-sized box) goes in a short list every query reads instead. Height is checked against the bounds,
not hashed, since a game's colliders spread over the ground.

The systems that keep it, all in `after_input`, in this order:

| System | Does |
|---|---|
| `ForgetBoxes`, `ForgetCapsules`, `ForgetCharacters`, `ForgetMeshes`, `ForgetSpheres` | take out the collider of every entity whose shape was removed (`Removed<T>`) |
| `IndexBoxes`, `IndexCapsules`, `IndexCharacters`, `IndexMeshes`, `IndexSpheres` | index every shape just added (`Added<T>`) |
| `ReadCharacters`, `ReadKinematic` | read the transform of every character and kinematic collider again |
| `SortColliders` | rebuilds the kinematic and character grids, and the static grid only when a static collider came or went |
| `TrackTriggers` | finds what overlaps each trigger ([below](#triggers)) |

So queries made from `update` on see every collider where it stood at the start of the tick. The static grid
costs nothing on a tick where no static collider changes; the others are rebuilt from scratch every tick, which is
one pass over their entries.

## The narrow phase

Every shape is a core grown by a radius: a sphere is a point, a capsule a segment, a box and a triangle have no
radius. Testing two shapes is measuring the distance between their cores: segment to segment, to a box and to a
triangle, each exact, with the closest point on each side. Two shapes overlap when that distance is at most the sum
of their radii; two boxes, and a box and a triangle, are tested by separating axes.

A sweep moves a shape along a line and finds where it first touches another. The distance between the two as the
first moves is a convex function of how far it has moved, so each step goes to where the tangent line reaches
contact, which never passes the real contact: a sweep can only stop short, never tunnel through a thin wall, and it
needs a few steps (one, against a flat face). A sweep that does not close the distance at all stops at once, which
is what makes sliding along a floor or a wall cheap. Contact means within 1 mm.

A sweep that starts touching or inside a shape reports a hit at distance 0 if it moves further in, and ignores the
shape if it moves out, so a character resting on the floor walks away from it freely.

## Queries

Queries are functions of `Physics.Colliders`, answered at once against every solid collider (triggers and
characters are not solid). Each returns whether it hit, and fills a `Physics.Hit` with the nearest hit:

| Call | Finds |
|---|---|
| `colliders.raycast(origin_x, origin_y, origin_z, direction_x, direction_y, direction_z, maximum_distance, hit)` | the first collider along a ray |
| `colliders.sweep_sphere(center_x, center_y, center_z, radius, direction_x, direction_y, direction_z, maximum_distance, hit)` | the first collider a moving sphere touches |
| `colliders.sweep_capsule(start_x, start_y, start_z, end_x, end_y, end_z, radius, direction_x, direction_y, direction_z, maximum_distance, hit)` | the same for a capsule given by its segment's two ends |

The direction need not be normalised. `Physics.Hit` holds:

| Field | Is |
|---|---|
| `entity` | the collider's entity, an `Entity` of its own for each hit |
| `distance` | how far along the direction the shape moved before touching |
| `point_x`, `point_y`, `point_z` | the point of contact, on the collider's surface |
| `normal_x`, `normal_y`, `normal_z` | the collider's surface normal there, pointing back at the query |

```gdscript
type Aiming {
    transform: Transform.Component.Transform
    sight: Component.Sight
}

var colliders = Physics.Colliders()
var hit = Physics.Hit()

func update_each(aiming: Aiming) {
    var eye = aiming.transform
    var eye_y = eye.position_y + 1.5
    aiming.sight.distance = 40.0
    if colliders.raycast(eye.position_x, eye_y, eye.position_z, 1.0, 0.0, 0.0, 40.0, hit) {
        aiming.sight.distance = hit.distance
    }
}
```

Like every resource, `Physics.Colliders` counts as written by every system that binds it, so two systems that query
never share a stage with each other or with the physics systems; they share stages with everything else.

## Characters

A character is moved by a kinematic controller: a capsule standing upright, whose transform's position is its feet.
The game says where it wants to go, and the controller moves it there as far as the colliders allow.

| Component | Holds | Means |
|---|---|---|
| `Physics.Component.Character` | `radius` (0.4), `height` (1.8), `step_height` (0.35), `slope_limit` (45, in degrees), `gravity` (9.81) | the capsule and how it walks |
| `Physics.Component.DesiredVelocity` | `velocity_x`, `velocity_y`, `velocity_z`, in metres a second | where the game wants it to go |
| `Physics.Component.VerticalSpeed` | `value` | its speed along y under gravity; a game jumps by setting it above zero |
| `Physics.Component.Grounded` | marker | it stands on the ground: a surface no steeper than `slope_limit` |
| `Physics.Bundle.Character(position_x, position_y, position_z)` | a `Transform` at the feet, `Character`, `DesiredVelocity`, `VerticalSpeed` | a character, ready to spawn |

```gdscript
var spawn = Physics.Bundle.Character(10.0, 0.0, 4.0)
spawn.desired.velocity_x = 3.0
var walker = world.create_entity_from_bundle(spawn)
```

`Physics.System.MoveCharacters` (`update`) moves every character once a tick by its desired velocity times the
tick's step:

- **It pushes out first.** A character a kinematic collider moved into is pushed back out along the contact normal.
- **On the ground it walks.** It sweeps its capsule along the horizontal motion and slides along whatever it meets,
  up to four times a tick, following the crease when two walls meet. A surface steeper than `slope_limit` is a
  wall: the slide keeps only the motion along it, so a character walking into a steep slope stops at its foot,
  and one walking into it at an angle slides along it. A gentle slope is walked up.
- **It steps up.** When a wall stops it, it tries again from `step_height` higher and drops back down; if that lands
  on ground no higher than `step_height` above where it stood and gets further, it keeps the step. Landing on the
  edge of a step counts when the surface just past the edge is walkable, so it climbs the step over a few ticks.
- **It stays on the ground.** After walking, it sweeps down by `step_height` and settles on any walkable surface
  there, so it follows a slope or a stair down instead of flying off. Finding none, it loses `Grounded` and falls.
- **In the air it falls.** `VerticalSpeed` gains gravity every tick, and the whole motion is swept and slid; landing
  on walkable ground adds `Grounded` and zeroes the vertical speed, and hitting a ceiling while rising stops the
  rise.

`Grounded` is added and removed only when it changes, so `Added<Physics.Component.Grounded>` is a landing and
`Removed<Physics.Component.Grounded>` a take-off. A game sets `DesiredVelocity` in `after_input` (where input becomes
state), so a tick's input moves the character in the same tick. Characters pass through one another; they collide
with every solid collider.

`physics_bench` moves 5,000 characters over a square kilometre among 10,000 turned boxes and 200 triggers: the
whole tick takes about 14 ms, of which `MoveCharacters` takes 11 ms (optimized, a shared 4-core machine), against
about 5 s a tick when every query tests every collider.

## Triggers

A collider with the marker `Physics.Component.Trigger` is a trigger volume. It blocks nothing; instead, every tick,
`TrackTriggers` finds the characters and kinematic colliders overlapping it. Each overlap is an entity:

| Component | On | Means |
|---|---|---|
| `Component.Parent` | the overlap | link: the trigger, so the overlap is despawned with it |
| `Physics.Component.Visitor` | the overlap | link: the character or collider inside |
| `Physics.Component.Entered` | the overlap | marker: it began since the last `TrackTriggers` |
| `Physics.Component.Left` | the overlap | marker: it ended; the overlap is despawned on the next `TrackTriggers` |

`TrackTriggers` runs in `after_input`. A new overlap is spawned with `Entered`, which the next `TrackTriggers` removes;
an overlap that ends gets `Left` and is despawned by the next `TrackTriggers`. So each marker lives from one
`TrackTriggers` to the next, and **every system sees each entry and each exit exactly once**, whatever its phase: a
system after `TrackTriggers` in the tick sees it that tick, one before sees it the next. A system reacts by asking
for the marker, and follows the `Parent` link to the trigger:

```gdscript
type Arrival {
    entered: Physics.Component.Entered
    parent: Component.Parent
    visitor: Physics.Component.Visitor
}

type Door {
    entity: Entity
    door: Component.Door
}

func update_each(arrival: Arrival, door: Door) {
    var opening = Component.Opening()
    door.entity.add_component(opening)
}
```

An overlap entity that exists without either marker is a visitor still inside, so a row of `Visitor` and `Parent`
lists everyone inside every trigger. A visitor despawned while inside leaves the same way, with its `Visitor` link
already gone.

---

Next: [Environments and networking](networking.md), one program built as a client, a server and a bot.
