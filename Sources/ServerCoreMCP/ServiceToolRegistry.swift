#if MCP
import MCP

/// An immutable catalog with standard SDK handlers for tool discovery and calls.
///
/// This is an in-process building block. `ServerCoreMCPVapor.ServiceMCPRoutes` authenticates its
/// local HTTP endpoint before dispatching requests here. Tool annotations do not
/// grant permissions. Create a new registry when the service's supported catalog changes.
public struct ServiceToolRegistry: Sendable {
    /// Registration errors that would otherwise make dispatch ambiguous.
    public enum RegistrationError: Error, Equatable, Sendable {
        /// Two definitions use the same protocol name; neither may silently replace the other.
        case duplicateName(String)
    }

    /// Tool definitions ordered by protocol name, independent of registration order.
    public let tools: [Tool]
    private let handlers: [String: ServiceTool]

    /// Creates a fixed catalog, refusing duplicate names before any server starts.
    /// - Parameter registrations: Definitions paired with their business handlers.
    public init(_ registrations: [ServiceTool]) throws {
        var handlers: [String: ServiceTool] = [:]
        for registration in registrations {
            let name = registration.definition.name
            guard handlers[name] == nil else { throw RegistrationError.duplicateName(name) }
            handlers[name] = registration
        }
        self.handlers = handlers
        self.tools = registrations.map(\.definition).sorted { $0.name < $1.name }
    }

    /// Builds an SDK server whose discovery and invocation use this same catalog.
    ///
    /// The caller owns its transport and shutdown. No socket, subprocess or live service is opened.
    /// The catalog fits in one page; a supplied pagination cursor is refused.
    /// - Parameters:
    ///   - name: Server implementation name reported during MCP initialization.
    ///   - version: Version of the hosting service reported during initialization.
    /// - Returns: A configured, not-yet-started official SDK server.
    public func makeServer(name: String, version: String) async -> Server {
        let server = Server(name: name, version: version, capabilities: .init(tools: .init(listChanged: false)))
        await server.withMethodHandler(ListTools.self) { parameters in
            guard parameters.cursor == nil else { throw MCPError.invalidParams("This catalog has no continuation page") }
            return .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard let registration = handlers[parameters.name] else {
                throw MCPError.invalidParams("Unknown tool")
            }
            return try await registration.invoke(parameters)
        }
        return server
    }
}

#endif
