# Funico MCP tooling prototype

The first local slice of the MCP plan: register a service tool once, then discover and invoke it
through the official Swift SDK. The dependency is pinned to **0.12.1**, with the resolved graph
tracked alongside this package. Requires Swift 6.1 or later.

This is a standalone development package inside Core. It adds no dependency or product to Core's
existing package, so current services and the native app keep their existing dependency graphs.

```bash
cd Dev/MCPTooling
swift test -j 2
swift run funico-mcp-demo
```

The demo prints the discovered `demo_status` tool and an `idle` structured result. It uses the SDK's
in-memory transport, opens no port, and never reads or controls a real service.

## Register once

The following is the complete executable in `Sources/MCPDemo/main.swift`:

```swift
import FunicoMCPTooling
import MCP

// A read-only fixture: it never reads or controls the real Invoices service.
let status = ServiceTool(definition: Tool(
    name: "demo_status",
    title: "Demo service status",
    description: "Read the status of an isolated demonstration service.",
    inputSchema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false]),
    annotations: .init(readOnlyHint: true, openWorldHint: false),
    outputSchema: .object([
        "type": "object",
        "properties": .object(["state": .object(["type": "string", "enum": .array(["idle"])])]),
        "required": .array(["state"]),
        "additionalProperties": false,
    ])
)) { parameters in
    guard parameters.arguments?.isEmpty != false else {
        throw MCPError.invalidParams("demo_status accepts no arguments")
    }
    return .init(
        content: [.text(text: "Demo service is idle.", annotations: nil, _meta: nil)],
        structuredContent: .object(["state": "idle"]),
        isError: false
    )
}

let registry = try ServiceToolRegistry([status])
let server = await registry.makeServer(name: "Funico MCP demo", version: "0.1.0")
let client = Client(name: "Generic SDK client", version: "0.1.0")
let pair = await InMemoryTransport.createConnectedPair()
do {
    try await server.start(transport: pair.server)
    let initialized = try await client.connect(transport: pair.client)
    let discovered = try await client.listTools()
    let response = try await client.send(CallTool.request(.init(name: "demo_status")))
    let result = try await response.value
    print("Connected to \(initialized.serverInfo.name)")
    print("Discovered: \(discovered.tools.map(\.name).joined(separator: ", "))")
    print("Result: \(result.structuredContent ?? .null)")
    await client.disconnect()
    await server.stop()
} catch {
    await client.disconnect()
    await server.stop()
    throw error
}
```

`ServiceTool` pairs the SDK's tool definition with its business handler. `ServiceToolRegistry`
installs the SDK's standard `tools/list` and `tools/call` handlers from those same registrations.
Discovery preserves schemas, titles and annotations, and uses a stable name order. Duplicate names,
unknown tools and invalid continuation cursors are refused. Domain failures remain tool results.

Handlers own argument validation and domain behavior. This prototype does not implement a JSON
Schema validator, authorization, a Vapor route, the Agent relay, or generated Manager controls.
An annotation such as `readOnlyHint` is metadata, not an authorization decision. Do not expose this
registry over HTTP before the planned authenticated host adapter and call-time policy exist.

## Checks

Seven tests exercise an actual SDK client/server handshake and discovery/call round trip, schema
and metadata preservation, duplicate registration, unknown calls, argument rejection, domain error
results and empty catalogs/pagination. `Scripts/check-documentation.sh` verifies the README example
matches the built demo and checks this module's DocC links without adding a documentation plugin.

Validated on 20 October 2026: all seven tests, the executable demo and DocC/example checks passed
on macOS with Swift 6.4 and Ubuntu 24.04 x86_64 with Swift 6.3.3. The Core workflow includes a
separate Linux job for this package; a local pass does not imply a completed GitHub Actions run.
