#if MCP && Vapor
import Foundation
import MCP
import ServerCoreMCP
import Vapor

/// Hosts a service registry through the official SDK's stateless HTTP transport.
///
/// This local Agent-to-service endpoint requires a separate shared credential. It is not an OAuth
/// endpoint for external clients. The host must bind loopback; never use a user access token here.
public struct ServiceMCPRoutes: Sendable {
    private let registry: ServiceToolRegistry
    private let token: String
    private let name: String
    private let version: String

    /// Creates a host with a mandatory, nonempty local credential.
    /// - Parameters:
    ///   - registry: the service-owned definitions and handlers.
    ///   - token: a randomly generated secret of at least 32 characters, provisioned outside code.
    ///   - name: MCP implementation name.
    ///   - version: service implementation version.
    /// - Throws: a configuration error for an absent or malformed credential.
    public init(registry: ServiceToolRegistry, token: String, name: String, version: String) throws {
        guard token.utf8.count >= 32, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw Abort(.internalServerError, reason: "Configure a private local MCP credential")
        }
        self.registry = registry; self.token = token; self.name = name; self.version = version
    }

    /// Installs the standard endpoint on `/mcp`, with a bounded body and no streaming/session state.
    /// Authenticate before the SDK sees the request. The SDK owns JSON-RPC parsing and negotiation.
    /// - Parameter routes: the loopback service's route group.
    public func register(on routes: any RoutesBuilder) {
        routes.on(.POST, "mcp", body: .collect(maxSize: "64kb")) { (request: Vapor.Request) async throws -> Vapor.Response in
            let supplied = request.headers.bearerAuthorization?.token ?? ""
            let expected = Array(token.utf8), actual = Array(supplied.utf8)
            var difference = expected.count ^ actual.count
            for index in expected.indices { difference |= Int(expected[index] ^ (index < actual.count ? actual[index] : 0)) }
            guard difference == 0 else { throw Abort(.unauthorized) }
            let server = await registry.makeServer(name: name, version: version)
            let transport = StatelessHTTPServerTransport()
            try await server.start(transport: transport)
            var headers: [String: String] = [:]
            for header in request.headers { headers[header.name] = header.value }
            let input = MCP.HTTPRequest(method: "POST", headers: headers,
                body: request.body.data.map { Data($0.readableBytesView) }, path: "/mcp")
            let output = await transport.handleRequest(input)
            await server.stop()
            var responseHeaders = HTTPHeaders()
            for (key, value) in output.headers { responseHeaders.add(name: key, value: value) }
            return Vapor.Response(status: .init(statusCode: output.statusCode), headers: responseHeaders,
                            body: .init(data: output.bodyData ?? Data()))
        }
    }
}
#endif
