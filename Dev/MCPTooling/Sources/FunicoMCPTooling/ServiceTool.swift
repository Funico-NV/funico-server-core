import MCP

/// One SDK tool definition and the service behavior that implements it.
///
/// Keep argument validation in the handler alongside the service's domain rules. A JSON Schema
/// describes those rules to clients; this registration layer does not enforce arbitrary schemas.
public struct ServiceTool: Sendable {
    /// Metadata and schemas advertised through the standard MCP tool catalog.
    public let definition: Tool
    let invoke: @Sendable (CallTool.Parameters) async throws -> CallTool.Result

    /// Binds a tool to its implementation once for discovery and invocation.
    ///
    /// - Parameters:
    ///   - definition: The SDK's tool metadata, including input/output schemas.
    ///   - invoke: Validates arguments and performs the service operation. Return an `isError`
    ///     result for a domain failure; throw an MCP protocol error for a malformed request.
    public init(
        definition: Tool,
        invoke: @escaping @Sendable (CallTool.Parameters) async throws -> CallTool.Result
    ) {
        self.definition = definition
        self.invoke = invoke
    }
}
