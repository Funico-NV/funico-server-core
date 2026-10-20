import FunicoMCPTooling
import MCP
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ServiceToolRegistryTests {
    private func fixture(_ name: String = "status") -> ServiceTool {
        ServiceTool(definition: Tool(
            name: name, title: "Service status", description: "Read a fixture status.",
            inputSchema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false]),
            annotations: .init(readOnlyHint: true, openWorldHint: false),
            outputSchema: .object([
                "type": "object", "properties": .object(["state": .object(["type": "string"])])
            ])
        )) { parameters in
            guard parameters.arguments?.isEmpty != false else { throw MCPError.invalidParams("No arguments expected") }
            return .init(
                content: [.text(text: "idle", annotations: nil, _meta: nil)],
                structuredContent: .object(["state": "idle"]), isError: false
            )
        }
    }

    private func connected(
        _ registrations: [ServiceTool],
        perform: (Client) async throws -> Void
    ) async throws {
        let registry = try ServiceToolRegistry(registrations)
        let server = await registry.makeServer(name: "Fixture service", version: "1.0.0")
        let client = Client(name: "Independent SDK client", version: "1.0.0")
        let pair = await InMemoryTransport.createConnectedPair()
        do {
            try await server.start(transport: pair.server)
            let initialized = try await client.connect(transport: pair.client)
            #expect(initialized.serverInfo.name == "Fixture service")
            #expect(initialized.capabilities.tools != nil)
            try await perform(client)
            await client.disconnect()
            await server.stop()
        } catch {
            await client.disconnect()
            await server.stop()
            throw error
        }
    }

    @Test func discoveryPreservesSchemasAndMetadataInStableOrder() async throws {
        let first = fixture("alpha"), last = fixture("zulu")
        try await connected([last, first]) { client in
            let catalog = try await client.listTools()
            #expect(catalog.tools == [first.definition, last.definition])
            #expect(catalog.nextCursor == nil)
        }
    }

    @Test func aNewRegistrationCanBeDiscoveredAndCalledWithoutAnotherDispatcher() async throws {
        try await connected([fixture("new_service_tool")]) { client in
            let discovered = try await client.listTools()
            let name = try #require(discovered.tools.first?.name)
            let pending = try await client.send(CallTool.request(.init(name: name)))
            let result = try await pending.value
            #expect(result.isError == false)
            #expect(result.structuredContent == .object(["state": "idle"]))
            #expect(result.content == [.text(text: "idle", annotations: nil, _meta: nil)])
        }
    }

    @Test func duplicateNamesCannotReplaceAHandler() throws {
        #expect(throws: ServiceToolRegistry.RegistrationError.duplicateName("status")) {
            try ServiceToolRegistry([fixture(), fixture()])
        }
    }

    @Test func unknownToolsAreProtocolErrors() async throws {
        try await connected([fixture()]) { client in
            let pending = try await client.send(CallTool.request(.init(name: "unregistered")))
            await #expect(throws: MCPError.self) { try await pending.value }
        }
    }

    @Test func domainValidationRemainsInTheServiceHandler() async throws {
        try await connected([fixture()]) { client in
            let pending = try await client.send(CallTool.request(.init(name: "status", arguments: ["unexpected": true])))
            await #expect(throws: MCPError.self) { try await pending.value }
        }
    }

    @Test func domainFailureResultsRemainToolResults() async throws {
        let failed = ServiceTool(definition: fixture().definition) { _ in
            .init(content: [.text(text: "Fixture is unavailable", annotations: nil, _meta: nil)], isError: true)
        }
        try await connected([failed]) { client in
            let result = try await client.callTool(name: "status")
            #expect(result.isError == true)
        }
    }

    @Test func anEmptyCatalogAndInvalidPaginationAreExplicit() async throws {
        try await connected([]) { client in
            let catalog = try await client.listTools()
            #expect(catalog.tools.isEmpty)
            await #expect(throws: MCPError.self) { try await client.listTools(cursor: "not-issued") }
        }
    }
}
