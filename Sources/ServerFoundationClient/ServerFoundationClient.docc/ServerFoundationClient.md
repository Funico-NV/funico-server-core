# ``ServerFoundationClient``

A WebSocket that reconnects, for clients that cannot afford to go quietly stale.

## Overview

```swift
import ServerFoundationClient

let deviceToken = "…"   // from the Keychain

let socket = ResilientWebSocket(
    // https becomes wss; the scheme is derived, never assumed.
    url: URL(string: "https://box.tailnet.ts.net:5910/v1/events")!,
    // Header, never the query string.
    headers: ["Authorization": "Bearer \(deviceToken)"]
)

for await event in await socket.events() {
    switch event {
    case .connected:
        print("live")
    case .message(let message):
        if let text = message.text { print(text) }
    case .disconnected(let error, let retryingIn):
        // A view can show "reconnecting in 4s" instead of silently freezing.
        print("dropped: \(error), retrying in \(retryingIn)")
    }
}
```

### Resuming instead of restarting

``ResilientWebSocket/init(connectionURL:headers:transport:backoff:logger:)`` re-evaluates its
closure before **every** attempt, so a reconnect can carry `?since=<sequence>` and backfill what it
missed rather than leaving a silent hole.

The closure is `@Sendable`, so it cannot capture a mutable `var`. Hold the cursor in something
`Sendable` and read it inside:

```swift
actor Cursor {
    private(set) var sequence: UInt64 = 0
    func advance(to next: UInt64) { sequence = next }
}
let cursor = Cursor()

let resuming = ResilientWebSocket(
    connectionURL: {
        let since = await cursor.sequence
        return URL(string: "https://box.tailnet.ts.net:5910/v1/events?since=\(since)")
    },
    headers: ["Authorization": "Bearer \(deviceToken)"]
)
```

The stream does **not** end when the connection drops — that is the entire point. It ends when
``ResilientWebSocket/close()`` is called, when the task is cancelled, or when `connectionURL`
returns `nil`.

### What this replaces

Three defects that ship today in `funico-invoices-api`'s view modifiers:

- They build their URL by concatenating a hardcoded `ws://`, so anything behind TLS — a Cloudflare
  Tunnel, a reverse proxy — cannot connect at all. `URL.webSocketURL` derives the scheme and
  returns `nil` rather than guessing. (It is an extension on Foundation's `URL`, so DocC cannot
  link to it or list it in Topics below.)
- They `break` out of the receive loop on the **first** error with no retry, so a server restart
  leaves a silently dead view until the user backgrounds and foregrounds the app.
- They have no way to resume, so a reconnect loses whatever arrived in between.

### Why full jitter

``WebSocketBackoff`` draws its delay uniformly from `0...ceiling` rather than using the ceiling.
With a fixed delay, N clients knocked off by one server restart all retry on the same tick — and
keep doing so, forever.

### Testing reconnection

The transport is behind ``WebSocketTransport`` so recovery can be tested without starting, killing
and restarting a real server inside a unit test. A scripted transport that fails a set number of
times makes it deterministic and millisecond-fast.

## Topics

### Connecting

- ``ResilientWebSocket``
- ``WebSocketBackoff``

### Messages

- ``WebSocketMessage``
- ``WebSocketEvent``

### Transports

- ``WebSocketTransport``
- ``WebSocketConnection``
- ``URLSessionWebSocketTransport``
- ``WebSocketError``
