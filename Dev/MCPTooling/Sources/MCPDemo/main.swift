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
