# ``ServerCoreVapor``

What a Vapor server adds on top of the shared vocabulary: API documentation hosting, and the agent
control channel.

> Note: this module's two entry points, `Application.exposeDocumentation(file:extension:in:)` and
> `Application.enableAgentControl(version:provider:logs:onShutdownRequest:)`, are extensions on
> Vapor's `Application`. DocC will not link to extensions of a dependency's type, so they are
> documented here in prose rather than in Topics below. Their doc comments are on the declarations.

## Overview

Two `Application` extensions, both one line at the call site.

```swift
import Vapor
import ServerKit   // the umbrella; re-exports Core, Logging and this module

let app = try await Application.make()
app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port = 5910

// Swagger UI at /api/docs, spec at /api/openapi
app.exposeDocumentation(in: Bundle.module)

// Opens the agent control channel — and does nothing at all when not running under an agent.
try await app.enableAgentControl(version: "1.4.16")

try await app.execute()
```

### The control channel

`enableAgentControl(version:provider:logs:onShutdownRequest:)` returns `nil` when
`FNC_CONTROL_PORT` is absent. That is the ordinary "someone ran this by hand" case, and it staying
silent is what lets the channel be adopted without changing how anyone runs the server today.

Under an agent it binds a **second** listener on `127.0.0.1` only — the main listener is `0.0.0.0`,
and these routes include one that stops the server:

```
GET  /control/health    { instanceID, uptime, version, state }
GET  /control/state     ServerState + [ServerJobStatus]
GET  /control/jobs      [ServerJobDescriptor]
POST /control/shutdown  202, then stop
WS   /control/events    ServerEventEnvelope stream
```

A server with no job concept adopts it by implementing one method — ``AgentControlProvider``
defaults `jobs()` and `jobStates()` to empty:

```swift
struct SchedulerControl: AgentControlProvider {
    func serverState() async -> ServerState { .online }
}

// Passing the LogStorage the process was bootstrapped with is what makes
// WS /control/events carry structured logs instead of nothing.
let logStorage = LogStorage()

try await app.enableAgentControl(
    version: "1.2.0",
    provider: SchedulerControl(),
    logs: logStorage
)
```

### Four deliberate choices

**A half-configured environment throws.** `FNC_CONTROL_PORT` absent means "not under an agent" and
stays quiet — but port-present-token-missing is a misconfiguration, and binding a shutdown route
with no authentication is not an acceptable way to recover from it.

**Responses encode through `AgentControlCoding`, not Vapor's global encoder.**
`ContentConfiguration.global` is process-wide and writable, so a server installing its own encoder
would silently change what the agent receives. The agent is not that server's API client.

**`shutdown` answers 202 before it exits.** A process that vanished mid-request is
indistinguishable from a crash — precisely the distinction the agent exists to make.

**The token does real work.** Loopback is not a trust boundary: any process running as the same user
can reach the port. On Linux `/proc/<pid>/environ` is `0400` and on macOS `ps -E` needs same-user or
root, so it is not readable *across* users — but a same-user process can read it. A `0600` Unix
domain socket would be tighter on Unix; that tightness is what is traded for Windows parity.

## Topics

### Agent control channel

- ``AgentControlProvider``
- ``StatelessAgentControlProvider``
- ``AgentControlServer``
- ``ControlTokenMiddleware``
