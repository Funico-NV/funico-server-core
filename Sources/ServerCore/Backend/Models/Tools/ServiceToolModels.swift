import Foundation

/// A JSON value carried across the Agent channel without coupling Core to an MCP SDK.
/// Values preserve objects, arrays and scalar types; secrets must not be supplied as tool arguments.
public enum ToolJSONValue: Sendable, Hashable, Codable {
    /// A JSON object, keyed by the service's schema property names.
    case object([String: ToolJSONValue])
    /// An ordered JSON array.
    case array([ToolJSONValue])
    /// A string, including enum choices.
    case string(String)
    /// A finite JSON number.
    case number(Double)
    /// A JSON boolean.
    case bool(Bool)
    /// An explicit JSON null.
    case null

    /// Decodes ordinary JSON, never Swift's enum representation.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let boolean = try? value.decode(Bool.self) { self = .bool(boolean) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([Self].self) { self = .array(array) }
        else { self = .object(try value.decode([String: Self].self)) }
    }

    /// Encodes ordinary JSON for SDK, Agent and HTTP consumers.
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let boolean): try value.encode(boolean)
        case .null: try value.encodeNil()
        }
    }
}

/// One service-owned MCP definition relayed by the Agent. Metadata never grants authorization.
public struct ServiceToolDefinition: Sendable, Hashable, Codable {
    /// Stable protocol name, scoped to this service.
    public var name: String
    /// Human-facing title, when the service provides one.
    public var title: String?
    /// What the action does, in the service's words.
    public var description: String?
    /// The complete advertised JSON Schema, without silently dropping constraints.
    public var inputSchema: ToolJSONValue
    /// Optional schema for structured results.
    public var outputSchema: ToolJSONValue?
    /// Informational MCP hint; the Manager still enforces operator authorization on every call.
    public var readOnlyHint: Bool?
    /// Digest of the definition used to reject a form built from a stale catalog.
    public var revision: String

    /// Creates relayed metadata. The Agent computes `revision` from the canonical SDK definition.
    /// - Parameters:
    ///   - name: protocol name.
    ///   - title: display title.
    ///   - description: behavior description.
    ///   - inputSchema: full argument schema.
    ///   - outputSchema: optional result schema.
    ///   - readOnlyHint: service-provided hint, not a permission.
    ///   - revision: definition digest.
    public init(name: String, title: String? = nil, description: String? = nil,
                inputSchema: ToolJSONValue, outputSchema: ToolJSONValue? = nil,
                readOnlyHint: Bool? = nil, revision: String) {
        self.name = name; self.title = title; self.description = description
        self.inputSchema = inputSchema; self.outputSchema = outputSchema
        self.readOnlyHint = readOnlyHint; self.revision = revision
    }
}

/// A tool call naming only the service's tool and validated arguments, never a URL or process.
public struct ServiceToolCall: Sendable, Hashable, Codable {
    /// Protocol tool name.
    public var name: String
    /// Definition digest the person reviewed before submitting.
    public var revision: String
    /// Non-secret inputs retained by the Agent's durable command journal.
    public var arguments: [String: ToolJSONValue]

    /// Creates a call against a specific advertised definition.
    /// - Parameters:
    ///   - name: tool name.
    ///   - revision: expected definition digest.
    ///   - arguments: schema-validated non-secret values.
    public init(name: String, revision: String, arguments: [String: ToolJSONValue] = [:]) {
        self.name = name; self.revision = revision; self.arguments = arguments
    }
}

/// A bounded, text/structured MCP result. Acceptance of a job is distinct from its completion.
public struct ServiceToolResult: Sendable, Hashable, Codable {
    /// Service-supplied text suitable for an escaped result view.
    public var content: [String]
    /// Structured state or acceptance details, when available.
    public var structuredContent: ToolJSONValue?
    /// A domain failure reported by the service, rather than a transport failure.
    public var isError: Bool

    /// Creates a result without claiming that an accepted business job has finished.
    /// - Parameters:
    ///   - content: plain text messages.
    ///   - structuredContent: optional structured data.
    ///   - isError: whether the service refused or failed the action.
    public init(content: [String], structuredContent: ToolJSONValue? = nil, isError: Bool = false) {
        self.content = content; self.structuredContent = structuredContent; self.isError = isError
    }
}
