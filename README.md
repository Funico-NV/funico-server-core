# funico-server-core

The shared foundation for every Funico server, the deploy agent and the Server Manager app.
Formerly **funico-server-foundation** — see [Moving from funico-server-foundation](#moving-from-funico-server-foundation).

## Platform Compatibility
![Swift Tests](https://github.com/Funico-NV/funico-server-core/actions/workflows/swift_tests.yml/badge.svg)

macOS 13+ · iOS 17+ · tvOS 17+ · watchOS 10+ · visionOS 1+ · Linux

## Products

The package is split into layered products, so that clients — the Server Manager app and the
deploy agent — can depend on the shared models without pulling in Vapor.

| Product | Depends on | Use it from |
|---|---|---|
| `ServerKit` | Core + Logging; + Vapor with the `Vapor` trait | Umbrella. Re-exports Vapor only when the trait is enabled. |
| `ServerCore` | *nothing* | Anywhere — apps, clients, the agent |
| `ServerCoreLogging` | Core, swift-log | Servers, the agent, the app |
| `ServerCoreVapor` | Core, Logging, Vapor with the `Vapor` trait | Vapor servers only |
| `ServerCoreClient` | Core, Logging, swift-log | The app and the agent |
| `ServerCoreTesting` | Core | Tests and SwiftUI previews: in-memory backends |

`ServerCore` has zero dependencies and must stay that way — it is what makes the package
importable from an iOS target.

`ServerCoreClient` is **not** in the umbrella. Servers have no use for a client, and keeping it
out means importing `ServerKit` never drags in URLSession machinery.

Vapor is behind a SwiftPM trait and is **not enabled by default**. A package that imports
`ServerCoreVapor`, or expects `ServerKit` to re-export Vapor extensions, must enable
the trait in its package dependency:

```swift
.package(
    url: "https://github.com/Funico-NV/funico-server-core",
    from: Version(3, 0, 0),
    traits: ["Vapor"]
)
```

## What's in them

**`ServerCore`** — `APIModel`, `APIModelError`, `Query`, `SQLQuery`, plus the shared server
vocabulary: `ServerState`, `ServerJob`, `ServerJobState`, `ServerJobResult`,
`ServerJobDescriptor`, `ServerJobCapability`.

It also holds what the deploy agent, the Manager API and the app share to operate services on a
host: identifiers (`ServerID`, `ServiceID`, `DeploymentID`, `CommandID`, `AgentID`), status
(`ServiceStatus`, `ServerResources`), releases (`ReleaseInfo`, `ArtifactManifest`), deployments
(`DeploymentStage`, `DeploymentState`), logs (`LogEntry`, `LogQuery`), the agent protocol
(`AgentCommand`, `CommandEnvelope`, `AgentMessage`, `ManagerMessage`), `ServerCoreError`, and the
protocols an agent implements: `ServiceBackend`, `LogSource`, `DeploymentExecutor`, `HealthProbe`,
`ResourceSampler`, plus `ReleaseSource` for the Manager.

```swift
import ServerCore

// What the Manager sends an agent to restart a service. A service is only ever named by ID;
// the host decides what that ID means.
let frame = ManagerMessage(body: .command(CommandEnvelope(
    issuedBy: "user-subject",
    command: .perform(.restart, service: "invoices")
)))
let data = try AgentProtocol.encoder.encode(frame)
```

**`ServerCoreTesting`** — in-memory `MockServiceBackend`, `MockLogSource`,
`MockDeploymentExecutor`, `MockHealthProbe`, `MockResourceSampler` and `MockReleaseSource`. Each
honours the real contract — an unlisted service is refused, logs page by cursor — and records what
it was asked:

```swift
import ServerCore
import ServerCoreTesting

let backend = MockServiceBackend(services: [
    ServiceDescriptor(id: "invoices", displayName: "Invoices", backend: .systemd)
])
try await backend.perform(.restart, on: "invoices")
let state = try await backend.status(of: "invoices").activeState   // .active
```

**`ServerCoreLogging`** — `FNCLog`, `LogStorage`, `MemoryLogHandler`, `ServerEventEnvelope`.
Bootstrapping the handler is all a server needs to get a live log stream:

```swift
let storage = LogStorage()
LoggingSystem.bootstrap { _ in MemoryLogHandler(storage: storage) }
```

**`ServerCoreVapor`** — `Application.exposeDocumentation`, and the agent control channel.

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

**`ServerCoreClient`** — `ResilientWebSocket`, `WebSocketBackoff`, `URL.webSocketURL`.

```swift
import ServerCoreClient

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

`ServerCoreLogging` declares `Logger.MetadataValue: @retroactive Codable`, and so does
`InvoicesAPI` 1.2.5. Only one module in a process may. **Do not import both into the same target**
until `funico-invoices-api` 1.3.0 removes its copy.

### Moving from funico-server-foundation

3.0.0 renamed the package, its repository and its products. The types inside did not change.

| 2.x | 3.x |
|---|---|
| package `funico-server-foundation` | `funico-server-core` |
| `ServerFoundation` (umbrella) | `ServerKit` |
| `ServerFoundationCore` | `ServerCore` |
| `ServerFoundationLogging` | `ServerCoreLogging` |
| `ServerFoundationVapor` | `ServerCoreVapor` |
| `ServerFoundationClient` | `ServerCoreClient` |

**Step 1 — the URL.** Change the package URL and version; leave the products and imports alone. The
2.x product names still exist in 3.x as deprecated shims, each a single `@_exported import` of its
successor, so code written against 2.x compiles unchanged:

```diff
 .package(
-    url: "https://github.com/Funico-NV/funico-server-foundation",
-    from: Version(2,0,0),
+    url: "https://github.com/Funico-NV/funico-server-core",
+    from: Version(3,0,0),
     traits: ["Vapor"]
 )
 …
-.product(name: "ServerFoundation", package: "funico-server-foundation")
+.product(name: "ServerFoundation", package: "funico-server-core")
```

The `package:` argument changes because SwiftPM names a package after the last component of its URL.

**Step 2 — the imports, whenever convenient.** Swap each old product and `import` for its new name.
The shims are removed in 4.0.0.

**One graph, one name.** A dependency graph that reaches this package through both the old and the
new URL has two packages defining the same modules, and will not build. Within one graph — one
server and everything it depends on — move every reference together. Separate servers can move one at
a time: GitHub redirects the old URL and keeps the 1.x and 2.x tags, so an unmigrated consumer keeps
resolving as it does today.

### Upgrading from 1.x

Moving from 1.x also takes the 2.0 product split. Vapor servers must enable the `Vapor` trait, which
requires `swift-tools-version` 6.1 in the consumer:

```diff
 .package(
-    url: "https://github.com/Funico-NV/funico-server-foundation",
-    from: Version(1,0,0)
+    url: "https://github.com/Funico-NV/funico-server-core",
+    from: Version(3,0,0),
+    traits: ["Vapor"]
 )
```

With that trait enabled, `import ServerKit` (or the deprecated `import ServerFoundation`) re-exports
the split products. The umbrella uses `@_exported`, which is what makes
`Application.exposeDocumentation` still resolve — extension members are only visible when their
defining module is imported, so a typealias shim could not have delivered it.

`@_exported` is an underscored, formally unsupported attribute. Vapor relies on it and it is stable
on Swift 6.x, but it is not a language guarantee. If a future toolchain drops it, the fix is to
import the specific products directly in each consumer; the blast radius is
`Sources/ServerKit/ServerKit.swift` and the shims under `Sources/Compatibility/`.

### Depending on Core alone

```swift
.product(name: "ServerCore", package: "funico-server-core")
```

**Vapor is not resolved, built or linked by default.** SwiftPM traits require
`swift-tools-version` 6.1 in this package and in consumers that want to configure traits. Consumers
that depend only on Core, Logging, Client, or the default umbrella leave the `Vapor` trait disabled
and do not clone Vapor's transitive dependency graph.

## Dependency Versioning

Vapor is tracked with `from: 4.0.0` and swift-log with `from: 1.11.0`. This package is always
consumed as a dependency, so the resolving root owns the pins; the `Package.resolved` in this
repository only pins this package's own CI and local builds.
