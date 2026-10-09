//
//  MockAgentSigner.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// An `AgentSigner` with no cryptography at all, so the enrollment and handshake *policy* can be
/// tested — and previewed — without linking swift-crypto.
///
/// **Not a signature scheme.** A "signature" is the public key followed by a 64-bit FNV-1a hash of
/// the message: anyone can forge one. It is distinguishable enough for tests — a different key, or
/// different bytes, produce a different signature — and that is all it is for. Keys carry the
/// algorithm ``algorithm``, which a real verifier refuses, so a mock key cannot be enrolled with a
/// Manager that uses `Ed25519AgentSignatureVerifier` by mistake.
///
/// ```swift
/// let signer = MockAgentSigner()
/// let verifier = MockAgentSignatureVerifier()
/// let signature = try await signer.sign([1, 2, 3])
/// verifier.isValidSignature(signature, of: [1, 2, 3], by: signer.publicKey)   // true
/// ```
public struct MockAgentSigner: AgentSigner {

    /// The algorithm every mock key carries: `insecure-mock`.
    public static let algorithm = AgentKeyAlgorithm("insecure-mock")

    public let publicKey: AgentPublicKey

    /// Creates a signer with a random 32-byte key, so two signers never share one.
    public init() {
        var generator = SystemRandomNumberGenerator()
        self.init(keyBytes: (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// Creates a signer with a fixed key, for deterministic tests.
    ///
    /// - Parameter keyBytes: the key's bytes.
    public init(keyBytes: [UInt8]) {
        publicKey = AgentPublicKey(algorithm: Self.algorithm, rawRepresentation: keyBytes)
    }

    public func sign(_ message: [UInt8]) -> AgentSignature {
        Self.signature(of: message, by: publicKey)
    }

    static func signature(of message: [UInt8], by key: AgentPublicKey) -> AgentSignature {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.rawRepresentation + message {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let digest = (0..<8).reversed().map { UInt8(truncatingIfNeeded: hash >> ($0 * 8)) }
        return AgentSignature(rawRepresentation: key.rawRepresentation + digest)
    }
}

/// Verifies ``MockAgentSigner`` signatures. Refuses every key that is not a mock key.
public struct MockAgentSignatureVerifier: AgentSignatureVerifier {

    /// Creates a verifier.
    public init() {}

    public func isValidSignature(
        _ signature: AgentSignature,
        of message: [UInt8],
        by publicKey: AgentPublicKey
    ) -> Bool {
        publicKey.algorithm == MockAgentSigner.algorithm
            && signature == MockAgentSigner.signature(of: message, by: publicKey)
    }
}
