## Platform Compatibility
![Swift Tests](https://github.com/Funico-NV/funico-server-foundation/actions/workflows/swift_tests.yml/badge.svg)

macOS 13+ · iOS 17+ · tvOS 17+ · watchOS 10+ · visionOS 1+ · Linux

## Products

2.0.0 split the single `ServerFoundation` library into layered products, so that clients — the
Server Manager app and the deploy agent — can depend on the shared models without pulling in Vapor.

| Product | Depends on | Use it from |
|---|---|---|
| `ServerFoundation` | Core + Logging; + Vapor with the `Vapor` trait | Umbrella. Re-exports Vapor only when the trait is enabled. |
| `ServerFoundationCore` | *nothing* | Anywhere — apps, clients, the agent |
| `ServerFoundationLogging` | Core, swift-log | Servers, the agent, the app |
| `ServerFoundationVapor` | Core, Logging, Vapor with the `Vapor` trait | Vapor servers only |
| `ServerFoundationClient` | Core, Logging, swift-log | The app and the agent |

`ServerFoundationCore` has zero dependencies and must stay that way — it is what makes the package
importable from an iOS target.

`ServerFoundationClient` is **not** in the umbrella. Servers have no use for a client, and keeping it
out means importing `ServerFoundation` never drags in URLSession machinery.

Vapor is behind a SwiftPM trait and is **not enabled by default**. A package that imports
`ServerFoundationVapor`, or expects `ServerFoundation` to re-export Vapor extensions, must enable
the trait in its package dependency:

```swift
.package(
    url: "https://github.com/Funico-NV/funico-server-foundation",
    from: Version(2, 0, 0),
    traits: ["Vapor"]
)
```

## What's in them

**`ServerFoundationCore`** — `APIModel`, `APIModelError`, `Query`, `SQLQuery`, plus the shared server
vocabulary: `ServerState`, `ServerJob`, `ServerJobState`, `ServerJobResult`,
`ServerJobDescriptor`, `ServerJobCapability`.

**`ServerFoundationLogging`** — `FNCLog`, `LogStorage`, `MemoryLogHandler`, `ServerEventEnvelope`.
Bootstrapping the handler is all a server needs to get a live log stream:

```swift
let storage = LogStorage()
LoggingSystem.bootstrap { _ in MemoryLogHandler(storage: storage) }
```

**`ServerFoundationVapor`** — `Application.exposeDocumentation`, and the agent control channel.

### The agent control channel

One line in a managed server's `main`:

```swift
try await app.enableAgentControl(version: "1.4.16")
```

A server started by hand has no `FNC_CONTROL_PORT`, so this returns `nil` and changes nothing —
which is what lets the channel be adopted without changing how anyone runs the server today. Under
the agent it opens a **second** listener, bound to `127.0.0.1` only:

```
GET  /control/health    { instanceID, uptime, version, state }
GET  /control/state     ServerState + [ServerJobStatus]
GET  /control/jobs      [ServerJobDescriptor]
POST /control/shutdown  202, then stop
WS   /control/events    ServerEventEnvelope stream
```

All require `Authorization: Bearer <token>`, compared in constant time. A server with no job concept
adopts it by implementing one method — `AgentControlProvider` defaults `jobs()` and `jobStates()` to
empty, which is right for `funico-scheduler-api-server` and the dashboards.

Four things that are deliberate:

- **A second listener, not routes on the main one.** The main listener is `0.0.0.0`; these routes
  include one that stops the server, and must not be reachable from off-box.
- **A half-configured environment throws.** `FNC_CONTROL_PORT` absent means "not under an agent" and
  stays silent — but port-present-token-missing is a misconfiguration, and binding a shutdown route
  with no auth on it is not an acceptable way to recover.
- **Responses are encoded with `AgentControlServer.encoder`, not Vapor's global one.**
  `ContentConfiguration.global` is process-wide and writable, so a server that installs its own
  encoder would otherwise silently change what the agent receives. Clients should decode with
  `AgentControlServer.decoder`. Dates are ISO-8601.
- **`shutdown` answers 202 before it exits.** A process that vanished mid-request is
  indistinguishable from a crash, which is precisely the distinction the agent exists to make.

**Security tradeoff, stated plainly.** Loopback is not a trust boundary: any process running as the
same user can reach `127.0.0.1:<port>`, so the token is doing real work. On Linux
`/proc/<pid>/environ` is `0400` owner-only and on macOS `ps -E` needs same-user or root, so the token
is not readable *across* users — but a same-user process can read it. A `0600` Unix domain socket
would be strictly tighter on Unix; that tightness is what is traded for Windows parity, where
SwiftNIO's UDS support is unverified and Vapor's server config is hostname/port-shaped.

**`ServerFoundationClient`** — `ResilientWebSocket`, `WebSocketBackoff`, `URL.webSocketURL`.

```swift
import ServerFoundationClient

let deviceToken = "…"   // from the Keychain

let socket = ResilientWebSocket(
    // https becomes wss; the scheme is derived, never assumed.
    url: URL(string: "https://box.tailnet.ts.net:5910/v1/events")!,
    // Header, never the query string — a token in a URL lands in access logs.
    headers: ["Authorization": "Bearer \(deviceToken)"]
)

for await event in await socket.events() {
    switch event {
    case .connected:
        print("live")
    case .message(let message):
        if let text = message.text { print(text) }
    case .disconnected(let error, let retryingIn):
        // The stream does not end here — this is where a view shows "reconnecting".
        print("dropped: \(error) — retrying in \(retryingIn)")
    }
}
```

To resume rather than restart, use the `connectionURL:` initialiser, which is re-evaluated before
every attempt so the URL can carry `?since=<sequence>`. Note that the closure is `@Sendable` and so
cannot capture a mutable `var` — hold the cursor in something `Sendable` (an actor, or a lock-backed
box) and read it inside the closure.

This replaces three defects that ship today in `funico-invoices-api`'s view modifiers: they hardcode
`ws://` (so anything behind TLS cannot connect), they `break` out of the receive loop on the *first*
error with no retry (so a server restart leaves a silently dead view until the user backgrounds and
foregrounds the app), and they have no way to resume. `ResilientWebSocket` derives the scheme from
the base URL, reconnects with full-jitter exponential backoff, rebuilds the URL on every attempt so a
reconnect can carry `?since=<sequence>`, and sends credentials as a header rather than a query
parameter.

The transport is behind a protocol so reconnection is testable without starting, killing and
restarting a real server in a unit test.

### Two traps in the vocabulary

**`ServerJob` is a `String`-backed struct, not an enum.** `@AppStorage` requires
`RawRepresentable where RawValue == String`, so a protocol or existential loses persistence; a closed
enum keeps it but forces a foundation release plus an app rebuild for every new managed server.
The `Notification.Name` pattern gives both — per-server vocabularies are additive extensions.

**`ServerJobState` implements `Codable` by hand, and must keep doing so.** It conforms to both
`RawRepresentable` and `Codable`, and the standard library's
`extension RawRepresentable where RawValue: Codable, Self: Codable` defaults *take precedence over
the compiler's synthesis*. Delete the explicit implementation and JSON silently routes through the
lossy legacy string: `.finished(.failed("db down"))` encodes as `"canceled;…"` and decodes as
`.cancelled` — losing the failure reason on the exact path that exists to carry it. There is a test
for this.

### The legacy wire format is frozen

`ServerState.rawValue` and `ServerJobState.rawValue` produce `"id"` / `"id;iso8601"`, byte-identical
to `funico-invoices-api` 1.2.5. This is not merely a wire codec — it is `@AppStorage`'s *persistence*
codec on real devices, and the service cannot be upgraded atomically with an App Store build, so
changing it silently drops a user's saved job selection.

It is also deliberately not extended: no version field, no type tag, no room for a job result. All
new traffic uses `ServerEventEnvelope`, which is versioned JSON and carries a monotonic `sequence` so
a reconnect can resume with `?since=` instead of leaving a silent hole.

Verified by 117 differential checks against the real `InvoicesAPI` types across epoch, fractional,
pre-epoch, leap-day and far-future dates. That check cannot live in this repo — it would need a
dependency on `funico-invoices-api`, which depends on this package — so it belongs in
`funico-invoices-api`'s own test target when 1.3.0 adds the shims.

### Duplicate retroactive conformance, until invoices-api 1.3.0

`ServerFoundationLogging` declares `Logger.MetadataValue: @retroactive Codable`, and so does
`InvoicesAPI` 1.2.5. Only one module in a process may. **Do not import both into the same target**
until `funico-invoices-api` 1.3.0 removes its copy.

### Upgrading from 1.x

Core, Logging and Client consumers need only the version bump:

```diff
- .package(url: "https://github.com/Funico-NV/funico-server-foundation", from: Version(1,0,0)),
+ .package(url: "https://github.com/Funico-NV/funico-server-foundation", from: Version(2,0,0)),
```

Vapor servers must also enable the `Vapor` trait:

```diff
 .package(
     url: "https://github.com/Funico-NV/funico-server-foundation",
-    from: Version(2,0,0)
+    from: Version(2,0,0),
+    traits: ["Vapor"]
 )
```

With that trait enabled, `import ServerFoundation` keeps re-exporting the split products. The
umbrella uses `@_exported`, which is what makes `Application.exposeDocumentation` still resolve —
extension members are only visible when their defining module is imported, so a typealias shim could
not have delivered it.

`@_exported` is an underscored, formally unsupported attribute. Vapor relies on it and it is stable
on Swift 6.x, but it is not a language guarantee. If a future toolchain drops it, the fix is to
import the specific products directly in each consumer; the blast radius is
`Sources/ServerFoundation/ServerFoundation.swift`.

### Depending on Core alone

```swift
.product(name: "ServerFoundationCore", package: "funico-server-foundation")
```

**Vapor is not resolved, built or linked by default.** SwiftPM traits require
`swift-tools-version` 6.1 in this package and in consumers that want to configure traits. Consumers
that depend only on Core, Logging, Client, or the default umbrella leave the `Vapor` trait disabled
and do not clone Vapor's transitive dependency graph.

## Dependency Versioning

Vapor is tracked with `from: 4.0.0` and swift-log with `from: 1.11.0`. Neither is pinned in-repo;
`Package.resolved` is deliberately not committed, since this package is always consumed as a
dependency and the resolving root owns the pins.
