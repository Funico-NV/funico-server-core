# The agent protocol

How a deploy agent and the Server Manager talk over the one WebSocket the agent opens.

## Overview

The agent dials out; the Manager never connects to a host. Over that socket the Manager sends
``ManagerMessage`` frames and the agent answers with ``AgentMessage`` frames, all encoded through
``AgentProtocol/encoder`` and ``AgentProtocol/decoder`` so neither end's framework settings change
what the other receives.

### Commands

The Manager wraps an ``AgentCommand`` in a ``CommandEnvelope`` and sends it. The agent answers:

1. a ``CommandAck`` straight away — accepted and queued, or refused with a ``ServerCoreError``;
2. any number of ``CommandProgress`` updates, which are advisory and may be lost;
3. exactly one ``CommandResult``, the authoritative outcome.

```swift
import Foundation
import ServerCore

let restart = ManagerMessage(body: .command(CommandEnvelope(
    deadline: Date().addingTimeInterval(60),
    issuedBy: "user-subject",
    command: .perform(.restart, service: "invoices")
)))
let frame = try AgentProtocol.encoder.encode(restart)
```

``AgentCommand`` is the agent's whole attack surface. Every case names a service by ``ServiceID``;
none carries a command line, a unit name or a path, and none ever should.

### Exactly once

Commands are idempotent by ``CommandID``. The agent journals every one it accepts and answers a
repeated ID with the stored result instead of running it again, so a Manager that lost its
connection mid-restart simply sends the same envelope again. A command still queued at its
``CommandEnvelope/deadline`` is refused with ``ServerCoreError/Code/deadlineExceeded`` rather than
run late.

### Losing nothing on reconnect

Every ``AgentMessage`` has a ``AgentMessage/sequence``. The agent keeps the frames the Manager has
not confirmed, and the Manager confirms with ``ManagerMessage/Body/received(through:)`` once it has
stored them. After a reconnect the agent replays whatever is unconfirmed; the Manager drops
sequences it already has. Events — ``AgentEvent`` — ride the same numbering, so a status change
during an outage still arrives.

### Evolving it

``AgentProtocol/version`` changes only for a breaking change. New command kinds, event kinds and
frame types are additive: a receiver that does not know one decodes it as `unsupported` — refusing
an unknown command with ``ServerCoreError/Code/unsupportedCommand``, ignoring an unknown event —
rather than dropping the connection.

Enrollment and the signed challenge on connect are not part of this yet; they arrive with the agent
identity work.
