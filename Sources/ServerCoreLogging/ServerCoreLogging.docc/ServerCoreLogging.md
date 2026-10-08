# ``ServerCoreLogging``

Structured logging that a server produces, an agent relays, and an app renders — plus the versioned
envelope all three speak.

## Overview

Bootstrapping ``MemoryLogHandler`` is all a Funico server has to do to get a live log stream:

```swift
import Logging
import ServerCoreLogging

let storage = LogStorage()
LoggingSystem.bootstrap { _ in MemoryLogHandler(storage: storage) }

// Anything logged anywhere in the process is now both on stdout and in the ring.
Logger(label: "invoices").info("processing", metadata: ["batch": .string("2026-08")])

// A live, ordered stream — this is what the control channel serves over WS /control/events.
for await log in storage.stream(replayingExisting: true) {
    print("\(log.timestamp) [\(log.level)] \(log.message)")
}
```

### Why ``LogStorage`` is a class and not an actor

`LogHandler.log(event:)` is synchronous. An actor forces every call site into `Task { await … }`,
and unstructured tasks have no ordering guarantee — so log lines get **stored out of order**. That
is a real defect in the implementation this one replaces. A lock makes `append` synchronous and
ordering trivially correct.

It is also a true ring buffer. The original called `Array.removeFirst()` on every append past the
limit, moving 10,000 elements each time a chatty server logged a line.

### The envelope

``ServerEventEnvelope`` is the versioned JSON that all *new* traffic uses. It carries a monotonic
`sequence`, which is what makes a reconnect resumable: `?since=<sequence>` backfills what was missed
instead of leaving a silent hole.

It lives here rather than in `ServerCore` because it is the one type needing both the
domain vocabulary *and* ``FNCLog``, and Core must not gain a swift-log dependency. Anything
consuming this stream consumes logs anyway.

```swift
let envelope = ServerEventEnvelope(
    sequence: 41,
    serverID: "invoices",
    payload: .jobState(job: "Process", state: .finished(.failed("db down"), on: Date()))
)

print(envelope.topic)   // "jobs" — for filtering ?topics=state,jobs,log
```

### One conflict to know about

``FNCLog`` needs `Logger.Metadata` to be `Codable`, which swift-log does not provide, so this module
declares that conformance retroactively. `InvoicesAPI` 1.2.5 declares the same one. A binary linking
both builds and runs without a diagnostic — but which conformance wins is unspecified, and the two
agree only because one was copied from the other. `funico-invoices-api` 1.3.0 removes its copy.

### Into the host's log stream

The agent reads a host's logs as `ServerCore`'s `LogEntry`. A server's own ``FNCLog`` records join
that stream through `LogEntry.init(_:service:cursor:)`, an extension defined here because it is the
module that knows both types. swift-log's `trace` becomes `debug`, metadata is flattened to strings,
and the call site is kept as `source`, `file`, `function` and `line` fields. ``FNCLog``'s timestamp
carries no time zone, so convert on the host that wrote the record.

```swift
import Foundation
import ServerCore
import ServerCoreLogging

let record = FNCLog(
    level: .warning, message: "slow query", metadata: nil,
    source: "Invoices", file: #fileID, function: #function, line: #line
)
let entry = LogEntry(record, service: "invoices")
```

## Topics

### Logging

- ``FNCLog``
- ``LogStorage``
- ``MemoryLogHandler``

### Streaming events

- ``ServerEventEnvelope``
- ``ServerEventTopic``
