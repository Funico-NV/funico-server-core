# ``ServerCoreTesting``

In-memory implementations of ServerCore's service protocols, for tests and SwiftUI previews.

## Overview

Each mock honours the contract a real implementation must: refuse a service the host does not list
with `unknownService`, page logs by cursor without gaps, report every staging step before
activation. A test written against a mock therefore exercises the same paths it would against
systemd.

The mocks are actors (or plain structs where nothing changes), record what they were asked, and
can be told to fail. Nothing here depends on swift-testing or XCTest, so the app can use them in
previews too.

```swift
import ServerCore
import ServerCoreTesting

let backend = MockServiceBackend(services: [
    ServiceDescriptor(id: "invoices", displayName: "Invoices", backend: .systemd)
])

try await backend.perform(.restart, on: "invoices")
let status = try await backend.status(of: "invoices")   // .active
let asked = await backend.performed                      // [.restart of invoices]
```

## Topics

### Services

- ``MockServiceBackend``
- ``MockHealthProbe``
- ``MockResourceSampler``

### Logs

- ``MockLogSource``

### Releases and deployments

- ``MockDeploymentExecutor``
- ``MockReleaseSource``
