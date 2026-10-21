import Foundation

/// The deliberately bounded schema profile supported by the first generated action forms.
/// Unsupported keywords are refused, never silently discarded. Free text/secret arguments,
/// references, nested objects and unions need a later reviewed renderer and journal policy.
public struct ToolFormSchema: Sendable, Hashable {
    /// A field whose constraints are enforced both before dispatch and on the Agent.
    public struct Field: Sendable, Hashable {
        /// The supported input shapes.
        public enum Kind: Sendable, Hashable {
            /// An explicit finite string vocabulary.
            case choice([String])
            /// A finite number within inclusive bounds, optionally integral.
            case number(minimum: Double, maximum: Double, integer: Bool)
            /// An explicit true/false value.
            case boolean
        }
        /// Argument key from the service schema.
        public let name: String
        /// Display label from the service, falling back to the key.
        public let title: String
        /// Whether omission is refused.
        public let required: Bool
        /// Type and constraints to render and validate.
        public let kind: Kind
    }

    /// Stable argument-name ordering for generic controls.
    public let fields: [Field]

    /// Parses only the supported non-secret object profile.
    /// - Parameter schema: the complete service-advertised schema.
    /// - Throws: `invalidRequest` if any constraint cannot be represented and enforced.
    public init(_ schema: ToolJSONValue) throws {
        func invalid() -> ServerCoreError { .init(.invalidRequest, "This action uses an unsupported input schema") }
        guard case .object(let object) = schema,
              Set(object.keys).isSubset(of: ["type", "title", "description", "properties", "required", "additionalProperties", "$schema"]),
              object["type"] == .string("object"), object["additionalProperties"] == .bool(false),
              case .object(let properties) = object["properties"], properties.count <= 16 else { throw invalid() }
        let required: [String]
        if let value = object["required"] {
            guard case .array(let values) = value else { throw invalid() }
            required = try values.map { value in guard case .string(let name) = value else { throw invalid() }; return name }
        } else { required = [] }
        guard Set(required).count == required.count, Set(required).isSubset(of: Set(properties.keys)) else { throw invalid() }
        self.fields = try properties.sorted { $0.key < $1.key }.map { name, definition in
            guard !name.isEmpty, name.count <= 64, case .object(let field) = definition,
                  Set(field.keys).isSubset(of: ["type", "title", "description", "enum", "minimum", "maximum"]) else { throw invalid() }
            let title: String
            if let label = field["title"] { guard case .string(let text) = label else { throw invalid() }; title = text }
            else { title = name }
            let kind: Field.Kind
            switch field["type"] {
            case .string("string"):
                guard Set(field.keys).isDisjoint(with: ["minimum", "maximum"]), case .array(let values) = field["enum"],
                      !values.isEmpty, values.count <= 100 else { throw invalid() }
                let choices: [String] = try values.map { value in
                    guard case .string(let choice) = value, choice.count <= 128 else { throw invalid() }; return choice
                }
                guard Set(choices).count == choices.count else { throw invalid() }
                kind = .choice(choices)
            case .string("number"), .string("integer"):
                guard field["enum"] == nil, case .number(let minimum) = field["minimum"],
                      case .number(let maximum) = field["maximum"], minimum.isFinite, maximum.isFinite,
                      minimum <= maximum else { throw invalid() }
                kind = .number(minimum: minimum, maximum: maximum, integer: field["type"] == .string("integer"))
            case .string("boolean"):
                guard Set(field.keys).isDisjoint(with: ["enum", "minimum", "maximum"]) else { throw invalid() }
                kind = .boolean
            default: throw invalid()
            }
            return Field(name: name, title: title, required: required.contains(name), kind: kind)
        }
    }

    /// Enforces the same constraints the form displays, with no unknown keys or null coercion.
    /// - Parameter arguments: non-secret values to invoke.
    /// - Throws: `invalidRequest` for an omitted, unknown or invalid value.
    public func validate(_ arguments: [String: ToolJSONValue]) throws {
        guard Set(arguments.keys).isSubset(of: Set(fields.map(\.name))) else {
            throw ServerCoreError(.invalidRequest, "Unknown action argument")
        }
        for field in fields {
            guard let value = arguments[field.name] else {
                if field.required { throw ServerCoreError(.invalidRequest, "A required action argument is missing") }
                continue
            }
            let valid: Bool
            switch (field.kind, value) {
            case (.choice(let choices), .string(let choice)): valid = choices.contains(choice)
            case (.boolean, .bool): valid = true
            case (.number(let minimum, let maximum, let integer), .number(let number)):
                valid = number.isFinite && number >= minimum && number <= maximum && (!integer || number.rounded() == number)
            default: valid = false
            }
            guard valid else { throw ServerCoreError(.invalidRequest, "An action argument does not satisfy its schema") }
        }
    }
}
