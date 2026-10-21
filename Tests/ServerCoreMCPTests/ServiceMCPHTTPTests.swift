#if MCP && Vapor
import Foundation
import MCP
import ServerCoreMCP
import ServerCoreMCPVapor
import Testing
import Vapor
import VaporTesting

@Suite("Authenticated standard MCP HTTP")
struct ServiceMCPHTTPTests {
    actor Counter {
        var count = 0
        func call() { count += 1 }
    }
    @Test func authenticatesBeforeDispatchAndUsesStandardSDKMethods() async throws {
        let counter = Counter(), token = String(repeating: "a", count: 48)
        let registry = try ServiceToolRegistry([
            .init(definition: Tool(name: "execute_job", description: "Execute disposable job", inputSchema: .object(["type": "object"]))) { _ in
                await counter.call()
                return .init(content: [.text(text: "Accepted", annotations: nil, _meta: nil)], isError: false)
            }
        ])
        let app = try await Application.make(.testing)
        do {
            try ServiceMCPRoutes(registry: registry, token: token, name: "Fixture", version: "test").register(on: app)
            let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"execute_job","arguments":{}}}"#
            for credential in [nil, "wrong", token] {
                try await app.testing().test(.POST, "mcp", beforeRequest: { req in
                    req.headers.contentType = .json
                    req.headers.add(name: "Accept", value: "application/json, text/event-stream")
                    req.headers.add(name: "MCP-Protocol-Version", value: Version.latest)
                    if let credential { req.headers.bearerAuthorization = .init(token: credential) }
                    req.body = ByteBuffer(string: request)
                }) { response in
                    #expect(response.status == (credential == token ? .ok : .unauthorized))
                    if credential == token { #expect(response.body.string.contains("Accepted")) }
                }
            }
            #expect(await counter.count == 1)
        } catch { try await app.asyncShutdown(); throw error }
        try await app.asyncShutdown()
    }
}
#endif
