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

### Service logging in Server Manager

`ServerLogInjector` connects a service's swift-log calls to Server Manager. Bootstrap it **once,
before creating loggers or the Vapor application**, replacing any existing logging bootstrap:

```swift
import Logging
import ServerCoreLogging

let logs = ServerLogInjector(capacity: 10_000, minimumLevel: .info)
logs.bootstrap()

let logger = Logger(label: "invoices")
logger.info("Processing started", metadata: ["job": "sync", "batch": "2026-10"])
logger.error("Processing failed", metadata: ["job": "sync"])
```

For Vapor, enable the `Vapor` package trait and pass the same buffer to the control channel:

```swift
import Vapor
import ServerCoreVapor

let app = try await Application.make(.detect())
let control = try await app.enableAgentControl(version: "1.0.0", logs: logs.storage)
// Keep `control` for the service lifetime; call `try await control?.shutdown()` on shutdown.
```

To inject into a component without changing global logging, use
`let logger = logs.logger(label: "invoices", metadata: ["job": "sync"])` and pass that `Logger`
to the component. The same approach works with `app.logger = logs.logger(label: "invoices")`;
other loggers only participate if you bootstrap globally.

Each record goes to a bounded in-process buffer and immediately to stdout as
`<N>FNC_LOG:{...}`, with one JSON object per line. JSON preserves multiline messages and metadata;
`N` is the syslog priority. Under systemd, use `StandardOutput=journal` and
`SyslogLevelPrefix=yes` (the default), so journal priority filters also work. The Agent decodes
these records for the existing Manager service log screen, including search, severity filtering,
and live following. Ordinary stdout/stderr and malformed structured records remain readable.

The updated Agent stores service history in its own **SQLite database**, with configurable
`logs.retentionDays` per severity. On Linux it imports journald; on macOS it captures output from
host-configured process services. Journald retention still controls how much history can be
recovered after Agent downtime. The in-process buffer alone does not persist logs. Agent redaction
applies before persistence and forwarding. See the Agent README for retention and process setup.

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

- ``ServerLogInjector``
- ``FNCLog``
- ``LogStorage``
- ``MemoryLogHandler``

### Streaming events

- ``ServerEventEnvelope``
- ``ServerEventTopic``
