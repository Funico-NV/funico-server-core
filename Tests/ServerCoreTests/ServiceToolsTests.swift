import Foundation
import Testing
@testable import ServerCore

struct ServiceToolsTests {
    let schema: ToolJSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false),
        "properties": .object(["job": .object(["type": .string("string"), "enum": .array([.string("Mailing"), .string("Process")])])]),
        "required": .array([.string("job")])])

    @Test func wireRoundTripAndOptionalCapability() throws {
        let call = ServiceToolCall(name: "execute_job", revision: "definition", arguments: ["job": .string("Mailing")])
        let command = AgentCommand.callTool(service: "invoices", call: call)
        let bytes = try JSONEncoder().encode(command)
        #expect(try JSONDecoder().decode(AgentCommand.self, from: bytes) == command)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        #expect(object["kind"] as? String == "callTool")
        #expect(object["service"] as? String == "invoices")
        #expect(object["url"] == nil)
        let old = Data(#"{"id":"invoices","displayName":"Invoices","backend":"systemd","deploysEnabled":false}"#.utf8)
        #expect(try JSONDecoder().decode(ServiceDescriptor.self, from: old).toolsEnabled == nil)
    }

    @Test func schemaRejectsWrongTypesUnknownInputsAndUnsupportedConstraints() throws {
        let form = try ToolFormSchema(schema)
        try form.validate(["job": .string("Mailing")])
        #expect(throws: ServerCoreError.self) { try form.validate([:]) }
        #expect(throws: ServerCoreError.self) { try form.validate(["job": .string("mailing")]) }
        #expect(throws: ServerCoreError.self) { try form.validate(["job": .bool(true)]) }
        #expect(throws: ServerCoreError.self) { try form.validate(["job": .string("Mailing"), "url": .string("http://elsewhere")]) }
        guard case .object(var object) = schema else { return }
        object["allOf"] = .array([])
        #expect(throws: ServerCoreError.self) { _ = try ToolFormSchema(.object(object)) }
        object.removeValue(forKey: "allOf")
        object["properties"] = .object(["job": .object(["type": .string("string"), "writeOnly": .bool(true)])])
        #expect(throws: ServerCoreError.self) { _ = try ToolFormSchema(.object(object)) }
    }

    @Test func boundsAndOptionalValuesKeepTheirMeaning() throws {
        let form = try ToolFormSchema(.object(["type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(["minutes": .object(["type": .string("number"), "minimum": .number(0.1), "maximum": .number(720)]),
                                   "enabled": .object(["type": .string("boolean")])]), "required": .array([.string("minutes")])]))
        try form.validate(["minutes": .number(1), "enabled": .bool(false)])
        try form.validate(["minutes": .number(1)])
        #expect(throws: ServerCoreError.self) { try form.validate(["minutes": .number(0)]) }
        #expect(throws: ServerCoreError.self) { try form.validate(["minutes": .number(721)]) }
        #expect(throws: ServerCoreError.self) { try form.validate(["minutes": .number(.infinity)]) }
        #expect(throws: ServerCoreError.self) { try form.validate(["minutes": .null]) }
    }
}
