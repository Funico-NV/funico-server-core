import Foundation
import Testing
@testable import ServerCore

@Suite("Service definitions")
struct ServiceDefinitionTests {
    private let basic = #"{"schema":1,"service":"example","displayName":"Example","profile":"application","platforms":[{"os":"linux","arch":"x86_64","executable":"bin/Example"}]}"#

    private func decode(_ text: String) throws -> ServiceDefinition { try .decode(Data(text.utf8)) }
    private func definition(settings: [ServiceEnvironmentDefinition] = []) throws -> ServiceDefinition {
        try .init(service: "example", displayName: "Example", profile: "application",
            platforms: [.init(os: .linux, arch: .x86_64, executable: "bin/Example")], environment: settings)
    }
    private func manifest() -> ArtifactManifest {
        .init(service: "example", version: "1.0.0", gitCommit: "test", platform: .linuxX86_64,
              entrypoint: "bin/Example", files: ["bin/Example": String(repeating: "a", count: 64), ServiceDefinition.filename: String(repeating: "b", count: 64)])
    }

    @Test func exampleAndRoundTrip() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let example = try ServiceDefinition.decode(Data(contentsOf: root.appendingPathComponent("Packaging/Examples/funico-service.json")))
        #expect(example.service == "example")
        #expect(example.environment.contains { $0.name == "API_TOKEN" && $0.secret && $0.defaultValue == nil })
        #expect(try ServiceDefinition.decode(JSONEncoder().encode(example)) == example)
        let minimal = try decode(basic)
        #expect(minimal.environment.isEmpty && !minimal.requiresMigration)
        #expect(minimal.runtime(for: .linuxX86_64)?.executable == "bin/Example")
        #expect(minimal.runtime(for: .linuxAArch64) == nil)
    }

    @Test(arguments: ["/bin/sh", "../server", "bin/../server", "./server", "a//b", "a\\b", "C:/server.exe", "bin/server\n", "bin/server;echo", "bin/%2e%2e/server"])
    func unsafeExecutablesAreRefused(_ executable: String) {
        #expect(throws: ServerCoreError.self) { try ServiceRuntimeDefinition(os: .linux, arch: .x86_64, executable: executable) }
    }
    @Test func argumentsAreLiteralAndBounded() throws {
        let arguments = ["--name", "a b", "$(echo literal)", "`literal`", "$VALUE"]
        let runtime = try ServiceRuntimeDefinition(os: .macos, arch: .aarch64, executable: "bin/Example", arguments: arguments)
        #expect(runtime.arguments == arguments)
        #expect(throws: ServerCoreError.self) { try ServiceRuntimeDefinition(os: .linux, arch: .x86_64, executable: "bin/Example", arguments: ["bad\0value"]) }
        #expect(throws: ServerCoreError.self) { try ServiceRuntimeDefinition(os: .linux, arch: .x86_64, executable: "bin/Example", arguments: Array(repeating: "x", count: 33)) }
    }
    @Test func unsupportedAndUnknownFieldsFailClosed() throws {
        let runtime = #"{"os":"linux","arch":"x86_64","executable":"bin/Example"}"#
        var invalidDocuments: [String] = []
        invalidDocuments.append(basic.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2"))
        invalidDocuments.append(basic.replacingOccurrences(of: "\"profile\":\"application\"", with: "\"profile\":\"application\",\"installScript\":\"do something\""))
        invalidDocuments.append(basic.replacingOccurrences(of: runtime, with: String(runtime.dropLast()) + ",\"user\":\"root\"}"))
        invalidDocuments.append(basic.replacingOccurrences(of: "\"linux\"", with: "\"windows\""))
        invalidDocuments.append(basic.replacingOccurrences(of: "\"x86_64\"", with: "\"arm64\""))
        invalidDocuments.append(String(basic.dropLast()) + ",\"environment\":null}")
        invalidDocuments.append(String(basic.dropLast()) + ",\"readiness\":{\"port\":8080,\"path\":\"/health\",\"url\":\"https://remote.test\"}}")
        invalidDocuments.append(String(basic.dropLast()) + ",\"environment\":[{\"name\":\"TOKEN\",\"title\":\"Token\",\"type\":\"string\",\"required\":true}]}")
        invalidDocuments.append(String(basic.dropLast()) + ",\"environment\":[{\"name\":\"TOKEN\",\"title\":\"Token\",\"type\":\"string\",\"required\":true,\"secret\":true,\"value\":\"SECRET\"}]}")
        for text in invalidDocuments { #expect(throws: ServerCoreError.self) { try decode(text) } }
    }
    @Test func duplicatePlatformsNamesAndOversizedDocumentsAreRefused() throws {
        let runtime = try ServiceRuntimeDefinition(os: .linux, arch: .x86_64, executable: "bin/Example")
        #expect(throws: ServerCoreError.self) { try ServiceDefinition(service: "example", displayName: "Example", profile: "application", platforms: [runtime, runtime]) }
        let field = try ServiceEnvironmentDefinition(name: "PORT", title: "Port", type: .integer, required: true, secret: false)
        #expect(throws: ServerCoreError.self) { try definition(settings: [field, field]) }
        #expect(throws: ServerCoreError.self) { try ServiceDefinition.decode(Data(repeating: 32, count: 65_537)) }
        #expect(throws: ServerCoreError.self) { try decode(basic.replacingOccurrences(of: "\"example\"", with: "\"../example\"")) }
    }
    @Test func secretDefaultsAndValueErrorsNeverEchoCredentials() throws {
        let secret = "this-is-a-test-secret-$()"
        do {
            _ = try ServiceEnvironmentDefinition(name: "API_TOKEN", title: "Token", type: .string, required: true, secret: true, defaultValue: secret)
            Issue.record("A secret default was accepted")
        } catch { #expect(!String(describing: error).contains(secret)) }
        let field = try ServiceEnvironmentDefinition(name: "API_TOKEN", title: "Token", type: .string, required: true, secret: true)
        try field.validateValue(secret)
        #expect(throws: ServerCoreError.self) { try field.validateValue(secret + "\n") }
    }
    @Test(arguments: ["PATH", "LD_PRELOAD", "DYLD_INSERT_LIBRARIES", "BASH_ENV", "NODE_OPTIONS", "PYTHONPATH", "bad-name", "1BAD", "lowercase", ""])
    func runtimeControlNamesAreNotServiceSettings(_ name: String) {
        #expect(throws: ServerCoreError.self) { try ServiceEnvironmentDefinition(name: name, title: "Setting", type: .string, required: false, secret: false) }
    }
    @Test func settingConstraintsAndTypesAreEnforced() throws {
        let number = try ServiceEnvironmentDefinition(name: "PORT", title: "Port", type: .integer, required: true, secret: false, defaultValue: "8080", minimum: 1024, maximum: 65535)
        try number.validateValue("8081")
        for bad in ["80", "65536", "1.2", "08080", " 8080", "true"] { #expect(throws: ServerCoreError.self) { try number.validateValue(bad) } }
        let flag = try ServiceEnvironmentDefinition(name: "ENABLED", title: "Enabled", type: .boolean, required: true, secret: false)
        #expect(throws: ServerCoreError.self) { try flag.validateValue("1") }
        let url = try ServiceEnvironmentDefinition(name: "PUBLIC_URL", title: "Public URL", type: .url, required: true, secret: false)
        try url.validateValue("https://example.test/auth")
        for bad in ["file:///etc/passwd", "https://user:password@example.test", "https://example.test/#token", "https://example.test:99999"] { #expect(throws: ServerCoreError.self) { try url.validateValue(bad) } }
        #expect(throws: ServerCoreError.self) { try ServiceEnvironmentDefinition(name: "MODE", title: "Mode", type: .string, required: true, secret: false, defaultValue: "prod", choices: ["dev"]) }
        #expect(throws: ServerCoreError.self) { try ServiceEnvironmentDefinition(name: "MODE", title: "Mode", type: .boolean, required: false, secret: false, minimum: 0) }
    }
    @Test(arguments: ["https://remote.test/health", "//remote.test/health", "/../admin", "/a/./health", "/%2e%2e/admin", "/health?token=x", "/health#x", "/health\r\n", "/a\\b"])
    func readinessCannotEscapeLoopbackPath(_ path: String) {
        #expect(throws: ServerCoreError.self) { try ServiceReadinessDefinition(port: 8080, path: path) }
    }
    @Test func readinessBoundsAndManifestAgreement() throws {
        #expect(throws: ServerCoreError.self) { try ServiceReadinessDefinition(port: 80, path: "/health") }
        #expect(throws: ServerCoreError.self) { try ServiceReadinessDefinition(port: 8080, path: "/health", timeoutSeconds: 5, stableSeconds: 10) }
        let service = try definition()
        try service.validate(for: manifest())
        var invalidManifest = manifest()
        let sensitivePath = "../accidentally-supplied-credential"
        invalidManifest.files[sensitivePath] = String(repeating: "a", count: 64)
        do {
            try service.validate(for: invalidManifest)
            Issue.record("An invalid artifact manifest was accepted")
        } catch { #expect(!String(describing: error).contains(sensitivePath)) }
        for key in ["service", "entrypoint", "configKeys", "file", "platform", "health", "migration"] {
            var artifact = manifest()
            switch key {
            case "service": artifact.service = "another"
            case "entrypoint": artifact.entrypoint = "bin/Other"; artifact.files["bin/Other"] = String(repeating: "c", count: 64)
            case "configKeys": artifact.configKeys = ["DATABASE_URL"]
            case "file": artifact.files[ServiceDefinition.filename] = nil
            case "platform": artifact.platform = .linuxAArch64
            case "health": artifact.healthPath = "/health"
            default: artifact.requiresMigration = true
            }
            #expect(throws: ServerCoreError.self) { try service.validate(for: artifact) }
        }
    }
}
