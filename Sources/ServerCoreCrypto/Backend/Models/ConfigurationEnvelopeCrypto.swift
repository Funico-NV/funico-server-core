#if Crypto
import Crypto
import Foundation
import ServerCore

/// RFC 9180 HPKE (X25519/HKDF-SHA256/AES-256-GCM), using the maintained Swift Crypto implementation.
/// Enrollment-authenticated control channels establish the recipient key's identity; HPKE base mode
/// does not authenticate the Manager. API roles and Agent channel authentication remain mandatory.
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
public struct ConfigurationEnvelopeCrypto: Sendable {
    private let key = Curve25519.KeyAgreement.PrivateKey()
    /// New on each Agent start, preventing an old submission from becoming a recovered write.
    public let keyID = UUID().uuidString.lowercased()
    /// Generates an ephemeral recipient. Never serialize this value or persist its private key.
    public init() {}
    /// Base64 public key for snapshots; this is deliberately distinct from enrollment signing keys.
    public var recipientKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    private static let suite = HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_256)
    private static let info = Data("be.funico.service-configuration.v1".utf8)
    /// Encrypts an in-memory patch before creating a durable command; plaintext must not be persisted.
    public static func seal(_ patch: ServiceConfigurationPatch, recipientKey: String, context: ConfigurationEnvelopeContext) throws -> SealedServiceConfiguration {
        do {
            try patch.validate()
            guard let bytes = Data(base64Encoded: recipientKey), bytes.count == 32 else { throw invalid() }
            let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
            var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: suite, info: info)
            let ciphertext = try sender.seal(JSONEncoder().encode(patch), authenticating: context.authenticatedBytes())
            return .init(context: context, encapsulatedKey: sender.encapsulatedKey.base64EncodedString(), ciphertext: ciphertext.base64EncodedString())
        } catch { throw invalid() }
    }
    /// Opens only current, correctly bound, bounded submissions. Host policy still validates the changes.
    public func open(_ sealed: SealedServiceConfiguration, now: Date = Date()) throws -> ServiceConfigurationPatch {
        do {
            let current = Int64(now.timeIntervalSince1970)
            guard sealed.context.keyID == keyID, sealed.context.expiresAt > current, sealed.context.expiresAt <= current + 300,
                  sealed.encapsulatedKey.utf8.count <= 64, sealed.ciphertext.utf8.count <= 44_000,
                  let encapsulated = Data(base64Encoded: sealed.encapsulatedKey), encapsulated.count == 32,
                  let ciphertext = Data(base64Encoded: sealed.ciphertext), ciphertext.count <= 32_784 else { throw Self.invalid() }
            var recipient = try HPKE.Recipient(privateKey: key, ciphersuite: Self.suite, info: Self.info, encapsulatedKey: encapsulated)
            let data = try recipient.open(ciphertext, authenticating: sealed.context.authenticatedBytes())
            let patch = try JSONDecoder().decode(ServiceConfigurationPatch.self, from: data)
            try patch.validate()
            return patch
        } catch { throw Self.invalid() }
    }
    private static func invalid() -> ServerCoreError { .init(.verificationFailed, "Configuration envelope is invalid, expired or belongs to an earlier Agent process.") }
}
#endif
