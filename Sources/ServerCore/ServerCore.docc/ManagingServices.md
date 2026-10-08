# Managing services on a host

The vocabulary the deploy agent, the Manager API and the app share to watch, operate and deploy
services — and the protocols an agent implements to do it.

## Overview

A host runs **services**, each named by a ``ServiceID``. Which services exist is decided on the
host, in the agent's root-owned allow-list, never by the Manager: ``ServiceDescriptor`` is the
agent *describing* a listed service, and every command afterwards refers to it by ID only. A unit
name, a path or a command line never travels from the Manager to a host.

Four protocols separate what the agent does from how a particular host does it. The agent ships a
systemd implementation for Linux and a process-supervisor one for macOS; `ServerCoreTesting`
ships in-memory ones for tests and previews.

| Protocol | Answers |
|---|---|
| ``ServiceBackend`` | which services exist, what state they are in; start, stop, restart |
| ``LogSource`` | a page of a service's log, or a live stream of it |
| ``DeploymentExecutor`` | stage a release beside production, activate it, roll it back |
| ``HealthProbe`` | is the service actually serving, and on which version |

``ResourceSampler`` reports host load, and ``ReleaseSource`` — on the Manager, which holds the
GitHub credentials — lists releases with their ``ReleaseEligibility`` worked out.

```swift
import ServerCore

func restartAndReport(_ service: ServiceID, on backend: some ServiceBackend) async throws -> ServiceStatus {
    try await backend.perform(.restart, on: service)
    return try await backend.status(of: service)
}
```

### Status

``ServiceStatus`` uses systemd's vocabulary for every backend, so the app renders one set of
states. Decode is forgiving: a state a newer systemd invents arrives as
``ServiceActiveState/unknown`` rather than failing the whole status.

### Logs

``LogSource`` pages by cursor. Each ``LogEntry`` carries its position; passing the last one seen as
``LogQuery/afterCursor`` resumes with no gap and no repeat, which time-based paging cannot promise
when two lines share a timestamp. A query's text filter is a literal substring, never a pattern, so
a client cannot hand the host's regex engine something pathological. A page is at most
``LogQuery/maximumLimit`` entries.

### Deployments

A deployment moves through ``DeploymentStage``s in order. Everything up to and including
``DeploymentStage/preflight`` happens *beside* production — a failure there leaves the running
service exactly as it was. From ``DeploymentStage/activating`` on, production is touched, and a
failure means rolling back. ``DeploymentStage/touchesProduction`` is that line, and it decides what
an agent does when it restarts halfway through.

``DeploymentState`` records how it ended, and the terminal states say what the host is running:

```swift
import ServerCore

func summary(of state: DeploymentState) -> String {
    switch state {
    case .pending, .running: "in progress"
    case .succeeded: "running the new release"
    case .failed, .cancelled: "running the old release, untouched"
    case .rolledBack: "running the old release, restarted"
    case .rollbackFailed: "unknown, needs a person"
    }
}
```

The archive itself is described by its ``ArtifactManifest``. The agent treats it as untrusted even
after the signature checks out, and ``ArtifactManifest/validate()`` rejects anything that could
reach outside the release directory.

### Errors

Everything that crosses a process boundary fails with ``ServerCoreError``: a stable
``ServerCoreError/code`` to switch on and localise from, and a ``ServerCoreError/message`` for logs.
Codes are open, so a newer agent's code still decodes in an older app.
