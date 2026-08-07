## Platform Compatibility
![Swift Tests](https://github.com/Funico-NV/funico-server-foundation/actions/workflows/swift_tests.yml/badge.svg)

macOS 13+ · iOS 17+ · tvOS 17+ · watchOS 10+ · visionOS 1+ · Linux

## Products

2.0.0 split the single `ServerFoundation` library into layered products, so that clients — the
Server Manager app and the deploy agent — can depend on the shared models without pulling in Vapor.

| Product | Depends on | Use it from |
|---|---|---|
| `ServerFoundation` | Core + Logging + Vapor | Vapor servers. Umbrella; re-exports all three. |
| `ServerFoundationCore` | *nothing* | Anywhere — apps, clients, the agent |
| `ServerFoundationLogging` | Core, swift-log | Servers, the agent, the app |
| `ServerFoundationVapor` | Core, Logging, Vapor | Vapor servers only |
| `ServerFoundationClient` | Core, Logging, swift-log | The app and the agent |

`ServerFoundationCore` has zero dependencies and must stay that way — it is what makes the package
importable from an iOS target.

`ServerFoundationClient` is **not** in the umbrella. Servers have no use for a client, and keeping it
out means importing `ServerFoundation` never drags in URLSession machinery.

## What's in them

**`ServerFoundationCore`** — `APIModel`, `APIModelError`, `Query`, `SQLQuery`, plus the shared server
vocabulary added in 2.1.0: `ServerState`, `ServerJob`, `ServerJobState`, `ServerJobResult`,
`ServerJobDescriptor`, `ServerJobCapability`.

**`ServerFoundationLogging`** — `FNCLog`, `LogStorage`, `MemoryLogHandler`, `ServerEventEnvelope`.
Bootstrapping the handler is all a server needs to get a live log stream:

```swift
let storage = LogStorage()
LoggingSystem.bootstrap { _ in MemoryLogHandler(storage: storage) }
```

**`ServerFoundationVapor`** — `Application.exposeDocumentation`.

**`ServerFoundationClient`** — `ResilientWebSocket`, `WebSocketBackoff`, `URL.webSocketURL`.

```swift
let socket = ResilientWebSocket(
    connectionURL: { baseURL.appending(queryItems: [.init(name: "since", value: "\(lastSequence)")]) },
    headers: ["Authorization": "Bearer \(deviceToken)"]
)

for await event in await socket.events() {
    // .connected / .message / .disconnected(error:retryingIn:)
}
```

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

One line, no source changes:

```diff
- .package(url: "https://github.com/Funico-NV/funico-server-foundation", from: Version(1,0,0)),
+ .package(url: "https://github.com/Funico-NV/funico-server-foundation", from: Version(2,0,0)),
```

`import ServerFoundation` keeps working exactly as before. The umbrella re-exports the split
products with `@_exported`, which is what makes `Application.exposeDocumentation` still resolve —
extension members are only visible when their defining module is imported, so a typealias shim
could not have delivered it.

`@_exported` is an underscored, formally unsupported attribute. Vapor relies on it and it is stable
on Swift 6.x, but it is not a language guarantee. If a future toolchain drops it, the fix is to
import the specific products directly in each consumer; the blast radius is
`Sources/ServerFoundation/ServerFoundation.swift`.

### Depending on Core alone

```swift
.product(name: "ServerFoundationCore", package: "funico-server-foundation")
```

**Vapor is not built or linked, but it is still resolved.** SwiftPM prunes unused dependencies from
the *build graph*, not from *dependency resolution* — so Vapor and its ~28 transitive packages will
still be cloned and still appear in your `Package.resolved`. Nothing of them is compiled. If that
checkout cost becomes a problem for the app, the fix is SwiftPM traits (requires raising
`swift-tools-version` to 6.1 across consumers) and it can be added without a breaking change.

## Dependency Versioning

Vapor is tracked with `from: 4.0.0` and swift-log with `from: 1.5.0`. Neither is pinned in-repo;
`Package.resolved` is deliberately not committed, since this package is always consumed as a
dependency and the resolving root owns the pins.
