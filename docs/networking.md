# Environments and networking

**Proposal** (Claude's, unconfirmed; Mortaro decides the API). Built and tested: `examples/click_counter_online` runs
a server-authoritative counter with a GUI client and headless bots, and `slop_network_plugin` replicates its state.

A game with several processes (a client, a game server, an auth server, a headless bot) is one program. Each process
is that program compiled for one **environment**, and contains only the code that environment runs.

## Environments are folders

The program declares its environment as a `Build` field, with the default it builds without a flag:

```gdscript
# examples/click_counter_online/build.spite
var environment = "client"
```

and its entry file says, once, which folders each environment gets. A `load` under an `if` on a `Build` field is
decided while compiling (D186), so a folder another environment loads is never read, compiled or linked:

```gdscript
# examples/click_counter_online/click_counter_online.spite
var build = Build()
var cookbook = Recipes.Cookbook()

func ClickCounterOnline() {
    load "../../slop"
    load "../../plugins/slop_network_plugin"
    if build.environment == "server" {
        load "server"
    }
    if build.environment == "client" or build.environment == "bot" {
        load "players"
    }
    if build.environment == "bot" {
        load "bot"
    }
    if build.environment == "client" {
        load "client"
        load "../../plugins/slop_window_plugin"
        # ... input, ui, render, vulkan, the theme
        cookbook.cook()
    }
    var app = App()
    app.run()
}
```

`spite click_counter_online --environment=server` builds the server; `--environment=bot` builds the bot.

That is the whole mechanism, and it keeps writing a system as simple as before:

- **Where a file lives says where it runs.** A folder the entry file loads is not a namespace segment, so
  `server/system/count_clicks.spite` is `System.CountClicks` and `client/component/count_label.spite` is
  `Component.CountLabel`, exactly as if they were at the root. Moving a system between environments is moving
  its file.
- **Shared code sits at the root.** The program's own `component/` (`ClickCount`, `ClickRequest`) is in every
  environment.
- **Several environments share a folder.** `players/` holds `JoinServer`, which both the client and the bot run.
  An MMO would have, say, `servers/` for everything the auth and game servers share.
- **Engine plugins follow the same rule.** Only the client loads the window, UI and Vulkan plugins, so the server
  and bot never contain them: the server is about 0.7 MB, the client 2.9 MB.
- **Nothing is checked at run time.** A system never asks where it runs.

What each build contains, from its generated C:

| Environment | Game systems |
|---|---|
| server | `Host`, `CountClicks`, `StopAfterLifetime` |
| client | `JoinServer`, `OpenMainWindow`, `SpawnCounter`, `RequestClick`, `ShowCount` |
| bot | `JoinServer`, `Play` |

The environment name is a `Build` field of the program, not something the engine defines: a game has whatever
environments it needs.

## Replication is declared on the component

A component says which environments own it, with a function the network plugin finds at compile time. Nothing is
registered.

```gdscript
# component/click_count.spite: state the server owns, mirrored to everyone connected
var clicks = 0

func mirrored_from(environment: String): Boolean {
    return environment == "server"
}
```

```gdscript
# component/click_request.spite: a message every environment except the server sends
var clicks = 1

func sent_from(environment: String): Boolean {
    return environment != "server"
}
```

- **`mirrored_from`**: state. In an environment where it answers true, every entity with the component is sent to
  every peer whenever its bytes change, and in full to a peer that has just connected. That is how a new client
  sees the counter where the server left it. The receiver keeps a mirror: the sender's world entity maps to its own
  world entity, and any other entity to a local one marked `Network.Component.Mirrored` (holding the sender's
  id).
- **`sent_from`**: a message. An entity carrying it is sent once and despawned. The receiver spawns an entity with
  the component, `Network.Component.Sender` (the connection's entity) and `Network.Component.Arrived`, which
  lives for one tick.
- Both are predicates on the environment's name, so one declaration can cover one environment or many.

### Entity fields travel as the receiver's entities

A replicated component may hold other entities in fields typed `Entity` (a monster's `target`, an item's `owner`).
The codec writes each such field as the sender's view of it and reads it back as the receiver's: an entity the sender
mirrors goes out as the id it has on the other side, and an id that arrives is turned into the receiver's mirror of
it, made on the spot if that entity has not arrived yet, so a pointer can arrive before what it points at. `Mirrors()`
(a core singleton) holds the table; `mirrors.local_of(remote)` answers the local entity for a remote id. A field
typed `Integer` is sent as it is.

### Who observes what

There are no players in the engine, only observers (Mortaro, 2026-09-27). An entity marked
`Network.Component.Observed` is sent only to the connections that observe it; an unmarked entity (world state, a
counter) is sent to every connection. An observation is its own entity, a child of the observed one:
`Network.Component.Observer { subject, observer }`, where `observer` is a connection entity. An entity has as many
Observer children as it has observers, and systems keep them up to date:

- an item has one Observer, its owner's connection;
- a monster or another player has one for every connection whose viewer is near it (`slop_interest_plugin`, below);
- private state, such as a player's own stats, lives on a separate entity whose only Observer is that player's
  connection, while the public entity is observed by everyone in sight.

```gdscript
var item_view = world.create_entity()
var observer = Network.Component.Observer()
observer.subject = item.id
observer.observer = owner_connection
item_view.add_component(observer)
```

(`subject` names the observed entity until the engine has a parent relation; both ids are proposals by Claude.)

The network plugin collects each connection's observed entities every tick (`Address`, in `present`). It keeps, per
connection, which entities the peer knows. An entity that becomes observed is sent in full, one that stays is sent
only the frames that changed since the last tick, and one that stops being observed or is despawned is sent a
removal frame (message `-3`), on which the receiver despawns its mirror. Each tick every replicated component is
encoded once into a per-entity buffer and compared, component by component, with the last tick (`Network.Frames`),
so an observer costs one copy per observed entity, not an encode. A component removed from an entity that lives on
(a buff ending, an item unequipped) becomes a component-removal frame (message `-4`, carrying the component's
message id) in that entity's changes, and the receiver removes it from its mirror.

### Area of interest

`slop_interest_plugin` observes by distance, as plain ECS a game can leave out. A connection entity with an
`Interest.Component.Viewer` (`entity`, whose `Transform` is where the peer looks from, and `radius`) is given an
`Interest.Component.Watching`, and every entity with `Spatial.Component.Indexed` is marked `Observed`. Every tick, in
`prepare`, `Gather` asks `Spatial.Grid` what each viewer sees in its entity's space and compares it with what it saw: it spawns an
Observer child only for an entity that came into range, and despawns one only for an entity that left. The work
follows how much changes, not how much is in sight.

```gdscript
var viewer = Interest.Component.Viewer()
viewer.entity = avatar.id
viewer.radius = 60.0
connection.add_component(viewer)
```

`interest_check` tests it across two processes: a bot sees 6 of 100 beacons, 11 after the server moves its eye, 10
after the server despawns one in view, and exactly the 3 stashes observed by its connection, never the 2 others, nor 10 beacons at the same
places in another space; a stash's `near` field, naming a beacon the bot cannot see yet, arrives as the bot's own
mirror of that beacon; a `Sealed` component the server removes from one stash disappears from the bot's mirror while the stash stays.

The game code is plain ECS on both sides:

```gdscript
# server/system/count_clicks.spite
type Request {
    request: Component.ClickRequest
    arrived: Network.Component.Arrived
}

type Counter {
    count: Component.ClickCount
}

func update_each(request: Request, counter: Counter) {
    counter.count.clicks = counter.count.clicks + request.request.clicks
}
```

The client spawns a `ClickRequest` when the button is clicked (`RequestClick`) and copies the mirrored
`ClickCount` into its label (`ShowCount`). The increment exists only in the server.

## slop_network_plugin

Connections are entities. Settings and state are components on the world entity:

| Component | On | Meaning |
|---|---|---|
| `Network.Component.Listen` | world | accept connections on `host` (default `127.0.0.1`; `0.0.0.0` for every address) and `port` |
| `Network.Component.Connect` | world | keep a connection to `host` and `port`, redialling a second after a failure |
| `Network.Component.Connection` | one entity per peer | its stream, and `fresh` until the first snapshot is sent |
| `Network.Component.Sender` | an arrived message | the connection entity it came from |
| `Network.Component.Arrived` | an arrived message | despawned at the end of the tick |
| `Network.Component.Mirrored` | a mirrored entity | the sender's entity id |

| Phase | System | Does |
|---|---|---|
| `input` | `Accept` | opens the listener, accepts every waiting connection |
| `input` | `Dial` | starts a connect on the thread pool and polls it; a failed dial waits 60 ticks |
| `after_input` | `Receive` | reads every socket, decodes each frame, mirrors state and spawns arrived messages |
| `last` | `Send` | encodes mirrored state once, picks each peer's frames by its area of interest, writes to every peer |
| `last` | `ForgetArrived` | despawns arrived messages |

Nothing blocks a frame: sockets are non-blocking and are polled once per tick, and the one call that can take
seconds (a TCP connect to a port nobody listens on) runs on the pool (D191).

### The wire

Binary, little-endian, one frame per component value:

```
u32  size        bytes after this field (8 + payload), at most 64 KiB
i32  message     a stable hash of the component's name (the same in every environment of the program)
i32  entity      the sender's entity id, -1 for its world entity, -2 for a message
...  payload     the fields in declaration order, written by the engine's derived codec (Pack<T>)
```

The codec is generated per class at compile time from its attributes: numbers as their bytes, `Boolean` as one
byte, `String` as a length and its bytes, lists as a count and their items, nested classes inline. It is the same
codec the asset cache uses.

State is compared as encoded bytes, so an unchanged component costs its encoding and nothing on the wire. A
fresh peer gets the last frame of every mirrored value.

**Validation.** Everything received is untrusted. A frame is copied out of the socket buffer only once it has fully
arrived, and decoded from an `Asset.Bytes` marked `untrusted`: a read past its end marks it failed instead of
crashing, and a list's count must fit in what is left. A connection is closed on a frame size outside 8 bytes to
64 KiB, a message id no component has, a payload that fails to decode, or one with bytes left over. The inbound
buffer stops reading at 1 MiB, so a peer that floods is slowed by TCP.

## Not built yet

In rough order of need:

- **Values inline in columns.** Components are heap objects today (see [performance.md](performance.md)). D204's
  `Vector<T>` with in-place borrows is the path, and it will let the codec copy a component's bytes instead of
  walking its fields. Short strings stored inline (D203, being built) remove the allocation per decoded name.
- **Change detection by write, not by comparing.** Encoding every mirrored value every tick to compare bytes is
  fine for a counter and wrong for a world. It needs `Changed<T>`, which needs the compiler to say what a system
  writes (item 109).
- **A handshake** carrying the environment and a hash of every replicated component, so mismatched builds refuse
  each other instead of misreading, and a compile-time check that no two components hash to the same message id.
- **Unreliable delivery** (UDP) for state that is superseded every tick, prediction, and rates.
- **Transport.** TCP through the library's `Socket` and its non-blocking calls (`accept_client_now`,
  `read_bytes_now`, `write_bytes_now`, `closed`), so the plugin has no code of its own for any operating system.
