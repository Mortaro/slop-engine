# Environments and networking

`examples/click_counter_online` runs a server-authoritative counter with a GUI client and headless bots, and
`slop_network_plugin` replicates its state.

A game with several processes (a client, a game server, an auth server, a headless bot) is one program. Each process
is that program compiled for one **environment**, and contains only the code that environment runs.

## Environments are folders

The program declares its environment as a `Build` field, with the default it builds without a flag:

```gdscript
# examples/click_counter_online/build.spite
var environment = "client"
```

and its entry file says, once, which folders each environment gets. A `load` under an `if` on a `Build` field is
decided while compiling, so a folder another environment loads is never read, compiled or linked:

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
  every peer whenever a system writes it ([`Changed<T>`](ecs.md#change-tracking)) and its bytes differ from what the
  peer holds, and in full to a peer that has just connected. That is how a new client
  sees the counter where the server left it. The receiver keeps a mirror: the sender's world entity maps to its own
  world entity, and any other entity to a local one marked `Network.Component.Mirrored` (holding the sender's
  id).
- **`sent_from`**: a message. An entity carrying it is sent once and despawned. The receiver spawns an entity with
  the component, `Network.Component.Sender` (the connection's entity) and `Network.Component.Arrived`, which
  lives until a handler consumes it (below). A message is the whole entity: every `sent_from` component it holds
  travels together and arrives on one entity (see [A message is an entity](#a-message-is-an-entity)).
- Both are predicates on the environment's name, so one declaration can cover one environment or many.
- **`sent_unreliably`**: a mirrored component whose value a system writes nearly every tick (a position, an aim)
  answers true, and its changes travel by datagram instead of TCP ([below](#unreliable-delivery)).

```gdscript
# component/drift.spite: written every tick by the server, superseded by the next write
var position = 0

func mirrored_from(environment: String): Boolean {
    return environment == "server"
}

func sent_unreliably(): Boolean {
    return true
}
```

An engine component is mirrored the same way: a file at the same path in the game's own folder reopens the class
and adds the function, as `examples/clock_check/component/ticking.spite` does for `Component.Ticking`:

```gdscript
# component/ticking.spite, beside the game's entry file: every Ticking the server holds is mirrored
func mirrored_from(environment: String): Boolean {
    return environment == "server"
}
```

### Entity fields travel as the receiver's entities

A replicated [link component](ecs.md#links-between-entities) holds another entity (a monster's `Target`, an item's
`Owner`), and each side reads it as its own entity. There is no network API for links: they are ordinary components,
replicated by `mirrored_from` or `sent_from` on their class like any other. On the wire an `Entity` field says whose
entity it is:

- an entity of the sender's own goes as its id; the receiver turns it into its mirror of that entity, made on the
  spot if it has not arrived yet, so a pointer can arrive before what it points at;
- a mirror goes as the id it has on the other side, marked (`-100 - id`), so a client naming a server monster
  through its mirror names the server's own entity, and the server uses it as it is;
- the world entity keeps its meaning on both sides.

A link whose entity is despawned on the sender is removed there in the same flush, so the removal travels like any
other and the receiver drops its copy; the receiver also removes it itself when the mirror of that entity goes.
Either way a link never names a gone entity on any side.

The receiver checks every arriving component's links before adding it. A link naming an entity that is dead or was
never made there (a client's `Target` naming a monster the server despawned while the message was in flight, or a
peer sending made-up ids) drops that component, and for a message, the whole message: nothing is added, nothing is
logged, and the connection stays open, since the race is not a bug in either side. Local code adding such a link
still crashes (see [ecs.md](ecs.md#links-between-entities)).

`Mirrors()` (a core singleton) holds the table; `mirrors.local_of(remote)` answers the local entity for a remote id.
A field typed `Integer` is sent as it is. `interest_check` tests both directions: a server-side `Near` arrives naming the
bot's mirror, a bot's `Target` message naming a beacon through its mirror reaches the server as the server's own
beacon, and once the server despawns that beacon, every stash's `Near` is gone on the bot too; the bot then sends a
`Target` naming that despawned beacon, which the server drops, and a valid one after it, which it judges. `wire_probe` checks the
same translation through a link component's codec.

### Who observes what

There are no players in the engine, only observers. An entity marked
`Network.Component.Observed` is sent only to the connections that observe it; an unmarked entity (world state, a
counter) is sent to every connection. An observation is its own entity, a child of the observed one (its
`Component.Parent`), holding the link `Network.Component.Observer`, which names the connection. An entity has as many
observations as it has observers, and systems keep them up to date:

- an item has one observation, naming its owner's connection;
- a monster or another player has one for every connection whose viewer is near it (`slop_interest_plugin`, below);
- private state, such as a player's own stats, lives on a separate entity whose only observation names that
  player's connection, while the public entity is observed by everyone in sight.

```gdscript
var observation = item.create_entity()
var observer = Network.Component.Observer()
observer.entity = owner_connection
observation.add_component(observer)
```

Both ends are links, so neither can dangle: despawning the observed entity despawns its observations (they are its
children), and despawning a connection removes its `Observer`, after which `ForgetObservations` despawns the
observation.

`Send` collects each connection's observed entities every tick from the observations. It keeps, per connection,
which entities the peer knows (a `Network.Known` table inside the system, keyed by the connection.
It cannot be links, because a despawned entity's id is still needed to tell the peer to drop its mirror,
and a link to it is gone in the same flush). An entity that becomes observed is sent in full, one that stays is sent
only the frames that changed since the last tick, and one that stops being observed or is despawned is sent a
removal frame (message `-3`), on which the receiver despawns its mirror. `Network.Frames` keeps, per entity, the
last frame of each of its mirrored components. Each tick only the values whose column stamped a write since the last
tick (and every value of an entity that has just appeared) are encoded; a frame whose bytes differ from the kept one
replaces it and joins that entity's changes. An entity nobody wrote costs a stamp check and nothing else, and an
observer costs one copy per observed entity, never an encode. A component removed from an entity that lives on (a
buff ending, an item unequipped) becomes a component-removal frame (message `-4`, carrying the component's message
id) in that entity's changes, and the receiver removes it from its mirror.

`replication_check` proves it across two processes: a gauge the server writes reaches the bot on every write, while
one no system writes (a system reads it every tick) arrives exactly once. `replication_bench` measures it: 10,000
mirrored entities of which 1% move each tick cost 2,000 bytes and about 1.4 ms of `Send` a tick (optimized).

### Area of interest

`slop_interest_plugin` observes by distance, as plain ECS a game can leave out. A connection entity with an
`Interest.Component.Viewer` (`radius`) and the link `Interest.Component.Viewpoint` (the entity whose `Transform` is
where the peer looks from) sees what is near that entity, and every entity with `Spatial.Component.Indexed` is marked
`Observed`. Every tick, in `prepare`, `Gather` asks `Spatial.Grid` what each viewer sees in its viewpoint's space and
compares it with the observations it made for that connection (marked `Interest.Component.InSight`, so observations a
game makes itself are left alone): it spawns an observation only for an entity that came into range, and despawns
one only for an entity that left. The work follows how much changes, not how much is in sight. A connection whose
viewpoint is despawned loses its `Viewpoint` and sees nothing new until it is given another.

```gdscript
var viewer = Interest.Component.Viewer()
viewer.radius = 60.0
connection.add_component(viewer)
var viewpoint = Interest.Component.Viewpoint()
viewpoint.entity = avatar
connection.add_component(viewpoint)
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
| `Network.Component.Listening` | world | marker: the listener is open |
| `Network.Component.Connect` | world | keep a connection to `host` and `port`, redialling a second after a failure |
| `Network.Component.Dialing` | world | marker: a dial is in flight (its job lives in the `Network.Dials` resource) |
| `Network.Component.Connected` | world | link: the connection entity the dial made; removed when that connection closes, which redials |
| `Network.Component.Connection` | one entity per peer | its stream |
| `Network.Component.Sender` | an arrived message | link: the connection entity it came from |
| `Network.Component.Arrived` | an arrived message | despawned once its request component is removed, or its connection closes |
| `Network.Component.Mirrored` | a mirrored entity | the sender's entity id |
| `Network.Component.Greeted` | a connection | marker: the peer's hello matched, so state and messages flow; a game waits for `Added<Network.Component.Greeted>` to start serving a peer |
| `Network.Component.Refused` | world | the dialer's: the server's build differs (`protocol`, `schema`, `environment` of the peer); `Dial` stops redialling |
| `Network.Component.ServerClock` | world | the dialer's estimate of the server's game clock: `offset` (milliseconds to add to its own), `round_trip`, `samples` |
| `Network.Component.FollowServerClock` | world | marker: this process's game clock follows the server's ([below](#the-server-owns-the-clock)) |
| `Network.Component.DropDatagrams` | world | for tests: drop every `every`th outgoing datagram that carries frames |

| Phase | System | Does |
|---|---|---|
| `input` | `CheckSchema` | on the first tick, hashes every replicated component and crashes if two share a message id |
| `input` | `Accept` | opens the listener (and the datagram socket, when a component is sent unreliably) and adds `Listening`, accepts every waiting connection |
| `input` | `Dial` | while there is no `Connected`: starts a connect on the thread pool (adding `Dialing`) and takes its socket once done; a failed dial waits 60 ticks |
| `input` | `ReadDatagrams` | reads every waiting datagram and hands it to the connection its token names |
| `input` | `FollowServerClock` | moves the game clock by the `ServerClock` offset, where `FollowServerClock` is set |
| `after_input` | `Receive` | checks the peer's hello, reads every socket and datagram, decodes each frame, mirrors state, spawns arrived messages, answers pings |
| `last` | `Send` | sends the hello, encodes what was written, picks each peer's frames by its area of interest, writes to every peer, and sends unreliable changes by datagram |
| `last` | `ForgetArrived` | despawns consumed messages; closes a connection with more than 256 unhandled |
| `last` | `ForgetOrphanedMessages` | despawns messages whose connection closed (their `Sender` went with it) |
| `last` | `ForgetObservations` | despawns an observation whose connection closed (its `Observer` went with it) |

Nothing blocks a frame: sockets are non-blocking and are polled once per tick, and the one call that can take
seconds (a TCP connect to a port nobody listens on) runs on the thread pool.

### A message lives until a handler consumes it

A handler consumes an arrived message by removing its request component
(`routed.entity.remove_component(Component.ChatRequest)`). `ForgetArrived` despawns only messages whose request
component is gone, so a handler whose condition is not met yet (a request that arrives before the join that makes
its player) simply sees it again next tick, and no message is lost.

- A connection holding more than 256 unhandled messages is closed, with an error naming the oldest one's
  component, so a missing handler or a flooding client shows at once. There is no timer.
- The messages of a closed or vanished connection are despawned.
- `Network.Component.Arrived.message` holds the codec id of the component the message carries.

### A message is an entity

Since a link holds only its entity (ecs.md), a request naming two entities (a cast naming its skill and its target,
a sale naming the merchant and the item) is one entity holding the request and a link for each:

```gdscript
var request = world.create_entity()
var cast = Component.CastRequest()
request.add_component(cast)
var target = Component.Target()
target.entity = monster
request.add_component(target)
var skill = Component.OfSkill()
skill.entity = known_skill
request.add_component(skill)
```

`Send` groups a message's frames per entity (`Network.Letters`): its own components first, then its links, and each
frame's entity field is `-2 - id` of the sender's message entity, so the receiver adds every frame with the same id
to one arrived entity. `Arrived.message` is the first frame's component, so the request component (not a link) is the
one a handler removes to consume it. A link naming an entity dead or unknown on the receiver drops the whole message.
`interest_check` sends a `Point` with its `Target` and the server judges only the pair.

For several events of one type in one tick (two `Grant`s to one player), make each event an entity of its own,
a child of its target (`player.create_entity()`), and let the handler despawn it once applied; a component on the
target holds only one value per type.

### The handshake

Two builds of one program agree on every replicated component only when they were compiled from the same source,
so each side's first frame is a hello: the protocol version and a hash of every replicated component, its class
name, whether it is mirrored, sent or sent unreliably, and each field's name and type in order (nested classes
walked the same way), combined so the order classes are found in does not matter. Nothing else is read before the
peer's hello, and nothing is sent to a peer before its hello matched:

- a match adds `Network.Component.Greeted` to the connection, and state and messages start to flow (a message
  spawned while no peer is greeted reaches nobody);
- a mismatch, or any other first frame, closes the connection on both sides with an error naming both hashes and
  the peer's environment, and the dialer's world entity gets `Network.Component.Refused`, so it stops redialling.
  A build never misreads another's bytes.

Message ids are hashes of the class names, so two classes can collide. `CheckSchema` hashes every replicated
component on the first tick and crashes, naming both classes and
`no_two_replicated_components_share_a_message_id`, when two share an id: rename one.

`handshake_check` runs a server, a "stranger" built with one more mirrored component (refused by both sides, having
mirrored nothing), then a matching bot, which the server still serves; a fourth build holding `Component.Moon` and
`Component.NPon`, whose names hash alike, crashes at startup.

### Unreliable delivery

TCP delivers every frame in order, so a lost packet holds back everything after it. For a value superseded every
tick that is the wrong trade, so a component that answers `sent_unreliably()` has its changes sent by UDP datagram,
while everything else (new entities in full, removals, messages, the handshake) stays on TCP:

- An acceptor opens a datagram socket on its listening port, and gives each connection a token in its hello. A
  dialer opens one on any port and knocks (a datagram holding only the token) every ten ticks until the acceptor
  says it heard it, which also tells the acceptor where the dialer's datagrams come from; the acceptor knocks back
  the same way. Until a side knows its datagrams arrive, its unreliable changes go by TCP.
- Every datagram carries the sender's tick, and every tick's TCP batch begins with the same tick. A datagram older
  than the newest tick seen on either channel is dropped, so a late packet never moves a value backwards.
- A value that stops changing is sent once more by TCP the first tick nobody writes it, so its final value arrives
  even when the datagram carrying it was lost.

`unreliable_check` drives a value up by one each tick for 60 ticks: the first half arrives by datagram, the second
half is dropped on purpose (`DropDatagrams`) and the final 60 still arrives, by TCP; a forged datagram stamped with
an old tick, moving the value to -999, is counted as stale and ignored.

### The server owns the clock

Each process has its own game clock (`Component.Frame.elapsed_milliseconds`), which timers read
([ecs.md](ecs.md#timers)). A dialer measures the acceptor's clock: it pings when the hello matched and every
60 ticks, the acceptor answers with its game time, and the dialer keeps the offset (smoothed over the samples) and
the round trip in `Network.Component.ServerClock` on its world entity. A process whose world entity has
`Network.Component.FollowServerClock` moves its own game clock by that offset, so its game time is the server's.

That is what mirroring a timer needs: a `Ticking` holds the game time it ends at, so a client following the server's
clock reads a mirrored `Ticking` as the server does, and its own `TickTimers` rings it at the same game time. A
running timer changes only when it starts, pauses, resumes or rings, so a mirrored one costs nothing on the wire
while it runs. `clock_check` starts the server's clock 1,000 seconds ahead and mirrors `Timer` and `Ticking` (by
reopening them, above); the bot, following the server's clock, sees the alarm ring within a few milliseconds of the
server's game time.

### The wire

Binary, little-endian, one frame per component value:

```
u32  size        bytes after this field (8 + payload), at most 64 KiB
i32  message     a stable hash of the component's name (the same in every environment of the program)
i32  entity      the sender's entity id, -1 for its world entity, -2 - id for a frame of the sender's message entity id
...  payload     the fields in declaration order, written by the engine's derived codec (Pack<T>)
```

Negative message ids are the plugin's own: `-3` despawn a mirror, `-4` remove one component (its message id
follows), `-5` the hello (protocol, schema hash, token, datagram port, environment), `-6` the tick that follows,
`-7` "your datagrams arrive", `-8` a ping (the dialer's clock) and `-9` its answer (that clock and the acceptor's
game time). A datagram is the connection's token and the sender's tick (two `i32`), then frames as above, at most
about 1,200 bytes.

The codec is generated per class at compile time from its attributes: numbers as their bytes, `Boolean` as one
byte, `String` as a length and its bytes, lists as a count and their items, nested classes inline. It is the same
codec the asset cache uses.

State is encoded only where it was written, and sent only where its bytes changed. A fresh peer gets the last frame
of every mirrored value.

**Validation.** Everything received is untrusted. A frame is copied out of the socket buffer only once it has fully
arrived, and decoded from an `Asset.Bytes` marked `untrusted`: a read past its end marks it failed instead of
crashing, and a list's count must fit in what is left. A connection is closed on a frame size outside 8 bytes to
64 KiB, a message id no component has, a payload that fails to decode, or one with bytes left over. The inbound
buffer stops reading at 1 MiB, so a peer that floods is slowed by TCP.

**Transport.** TCP through the library's `Socket` and its non-blocking calls (`accept_client_now`,
`read_bytes_now`, `write_bytes_now`, `closed`), and UDP through its `UdpSocket` (`receive_now`, `send_to`), so the
plugin has no code of its own for any operating system. A datagram whose token names no connection, or whose frames
fail to decode, is dropped without closing anything, since anyone can send one.

---

Next: [Performance](performance.md), measuring a build and keeping frames free of stutters.
