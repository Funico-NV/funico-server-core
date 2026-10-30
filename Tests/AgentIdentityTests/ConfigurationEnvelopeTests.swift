#if Crypto
import Foundation
import Testing
import ServerCore
import ServerCoreCrypto

@Suite("Encrypted configuration delivery")
struct ConfigurationEnvelopeTests {
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
    private func context(_ recipient: ConfigurationEnvelopeCrypto, server: ServerID = "host", service: ServiceID = "example", revision: String = String(repeating: "a", count: 64), expires: Int64? = nil) -> ConfigurationEnvelopeContext {
        .init(operation: UUID().uuidString.lowercased(), server: server, service: service, revision: revision,
              keyID: recipient.keyID, expiresAt: expires ?? Int64(Date().timeIntervalSince1970) + 120)
    }
    @Test func ciphertextRoundTripsAndJournalsNeverEncodePlaintext() throws {
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let recipient = ConfigurationEnvelopeCrypto()
        let patch = ServiceConfigurationPatch(changes: [.init(name: "API_TOKEN", action: .set, value: "very-private-marker")])
        let sealed = try ConfigurationEnvelopeCrypto.seal(patch, recipientKey: recipient.recipientKey, context: context(recipient))
        let opened = try recipient.open(sealed)
        #expect(opened.changes.first?.value == "very-private-marker")
        let command = AgentCommand.updateServiceConfiguration(sealed)
        let encoded = try JSONEncoder().encode(command)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("very-private-marker"))
        #expect(String(describing: patch) == "ServiceConfigurationPatch(<redacted>)")
        #expect(try JSONDecoder().decode(AgentCommand.self, from: encoded) == command)
        #expect(try JSONDecoder().decode(CommandResult.self, from: Data(#"{"command":"legacy","completedAt":0}"#.utf8)).configuration == nil)
    }
    @Test func contextTamperingOldKeysAndExpiredSubmissionsAreRejected() throws {
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let recipient = ConfigurationEnvelopeCrypto()
        let patch = ServiceConfigurationPatch(changes: [.init(name: "API_TOKEN", action: .set, value: "private")])
        let original = context(recipient)
        let sealed = try ConfigurationEnvelopeCrypto.seal(patch, recipientKey: recipient.recipientKey, context: original)
        let changed = ConfigurationEnvelopeContext(operation: original.operation, server: "other", service: original.service,
            revision: original.revision, keyID: original.keyID, expiresAt: original.expiresAt)
        #expect(throws: (any Error).self) { try recipient.open(.init(context: changed, encapsulatedKey: sealed.encapsulatedKey, ciphertext: sealed.ciphertext)) }
        #expect(throws: (any Error).self) { try ConfigurationEnvelopeCrypto().open(sealed) }
        #expect(throws: (any Error).self) { try recipient.open(sealed, now: Date(timeIntervalSince1970: Double(original.expiresAt))) }
        let expired = try ConfigurationEnvelopeCrypto.seal(patch, recipientKey: recipient.recipientKey,
            context: context(recipient, expires: Int64(Date().timeIntervalSince1970) - 1))
        #expect(throws: (any Error).self) { try recipient.open(expired) }
    }
    @Test func invalidChangesAreRejectedWithoutEchoingTheirValues() {
        for patch in [ServiceConfigurationPatch(changes: [.init(name: "API_TOKEN", action: .remove, value: "private")]),
                      .init(changes: [.init(name: "LD_PRELOAD", action: .set, value: "private")]),
                      .init(changes: [.init(name: "API_TOKEN", action: .set, value: "line\ninjection")]),
                      .init(changes: [.init(name: "API_TOKEN", action: .set, value: "private"), .init(name: "API_TOKEN", action: .remove)])] {
            #expect(throws: (any Error).self) { try patch.validate() }
        }
    }
}
#endif
