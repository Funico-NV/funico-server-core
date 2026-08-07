# ``ServerFoundationCore``

The vocabulary every Funico server, the agent and the app agree on — with no dependencies at all.

## Overview

Core holds two unrelated things that share one property: neither needs Vapor.

The **SQL and API-model** pieces (``Query``, ``SQLQuery``, ``APIModel``, ``APIModelError``) are what
the servers have always used. The **server vocabulary** (``ServerState``, ``ServerJob``,
``ServerJobState``) is what lets a manager app and a supervising agent talk about a server without
knowing what that server does.

Zero package dependencies is a requirement, not an accident. It is what makes this importable from
an iOS target and from the agent, neither of which can afford to link Vapor.

```swift
import ServerFoundationCore

// A job the server offers, described at runtime rather than compiled into the app.
let descriptor = ServerJobDescriptor(
    job: "Process",
    title: "Process invoices",
    autoStart: true,
    capabilities: [.start, .stop, .execute]
)

// What it is doing right now. `.finished` carries the result — a run that failed is
// distinguishable from one that was cancelled.
let state = ServerJobState.finished(.failed("database unreachable"), on: Date())

print(state.title)          // "Failed"
print(state.failureReason)  // Optional("database unreachable")
```

### Two traps

``ServerJob`` is a `String`-backed struct, not an enum. `@AppStorage` requires
`RawRepresentable where RawValue == String`, so a protocol or existential loses persistence
entirely; a closed enum keeps it but forces a foundation release and an app rebuild for every new
managed server. The `Notification.Name` pattern gives both — per-server vocabularies are additive
extensions.

``ServerJobState`` implements `Codable` **by hand**, and must keep doing so. It conforms to both
`RawRepresentable` and `Codable`, and the standard library's
`extension RawRepresentable where RawValue: Codable, Self: Codable` defaults take precedence over
the compiler's synthesis. Remove the explicit implementation and JSON silently routes through the
lossy legacy string: `.finished(.failed("db down"))` encodes as `"canceled;…"` and decodes as
`.cancelled`, losing the reason on the very path built to carry it.

### The legacy wire format

``ServerState/rawValue`` and ``ServerJobState/rawValue`` produce `"id"` / `"id;iso8601"`,
byte-identical to what `funico-invoices-api` 1.2.5 emits. This is not merely a wire codec — it is
`@AppStorage`'s *persistence* codec on real devices, and the service cannot be upgraded atomically
with an App Store build. Changing it silently drops a user's saved job selection.

It is also deliberately not extended: no version field, no type tag, no room for a job result. All
new traffic uses `ServerEventEnvelope` in `ServerFoundationLogging`.

## Topics

### Describing a server

- ``ServerState``

### Describing jobs

- ``ServerJob``
- ``ServerJobState``
- ``ServerJobResult``
- ``ServerJobDescriptor``
- ``ServerJobCapability``

### The agent control channel

- ``AgentControlConfiguration``
- ``AgentControlConfigurationError``
- ``ControlHealth``
- ``ControlState``
- ``ServerJobStatus``
- ``AgentControlCoding``

### SQL and API models

- ``Query``
- ``SQLQuery``
- ``APIModel``
- ``APIModelError``
