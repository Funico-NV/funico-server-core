//
//  Ed25519AgentSigner.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

#if Crypto
import Foundation
import Crypto
import ServerCore

/// An agent's Ed25519 key pair, signing with swift-crypto's `Curve25519.Signing`.
///
/// On Apple platforms swift-crypto forwards to CryptoKit; on Linux and Windows it uses its own
/// BoringSSL-derived implementation. Either way the signatures are standard RFC 8032 Ed25519 and
/// verify on any other platform.
///
/// ```swift
/// // At enrollment: generate, persist the private key 0600, never send it.
/// let signer = Ed25519AgentSigner()
/// let privateKey = signer.rawRepresentation          // 32 bytes — write to disk 0600
///
/// // At every start: load it back.
/// let loaded = try Ed25519AgentSigner(rawRepresentation: privateKey)
/// ```
public struct Ed25519AgentSigner: AgentSigner {

    private let privateKey: Curve25519.Signing.PrivateKey

    /// Generates a new key pair from the system's secure random source.
    public init() {
        privateKey = Curve25519.Signing.PrivateKey()
    }

    /// Loads a key previously saved from ``rawRepresentation``.
    ///
    /// - Parameter rawRepresentation: the 32-byte private key.
    /// - Throws: swift-crypto's error if the bytes are not a valid Ed25519 private key.
    public init(rawRepresentation: some ContiguousBytes) throws {
        privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    /// The 32-byte private key, for the agent to persist on its own host with mode `0600`.
    ///
    /// The one place the private key leaves this type. It must never leave the host: the protocol
    /// has no message that carries it, and nothing on the Manager can use it.
    public var rawRepresentation: Data {
        privateKey.rawRepresentation
    }

    /// The public key, algorithm `ed25519`, to send in an `AgentEnrollmentRequest`.
    public var publicKey: AgentPublicKey {
        AgentPublicKey(algorithm: .ed25519, rawRepresentation: [UInt8](privateKey.publicKey.rawRepresentation))
    }

    /// Signs a canonical payload. Never throws in practice; the signature is 64 bytes.
    ///
    /// - Parameter message: the canonical payload.
    /// - Returns: the signature.
    public func sign(_ message: [UInt8]) throws -> AgentSignature {
        AgentSignature(rawRepresentation: [UInt8](try privateKey.signature(for: message)))
    }
}

/// Verifies Ed25519 signatures with swift-crypto's `Curve25519.Signing`. What the Manager uses.
///
/// Refuses any key whose algorithm is not `ed25519`, any key that is not a valid 32-byte Ed25519
/// public key, and any signature that is not 64 bytes, before attempting verification.
public struct Ed25519AgentSignatureVerifier: AgentSignatureVerifier {

    /// Creates a verifier. It holds no state.
    public init() {}

    public func isValidSignature(
        _ signature: AgentSignature,
        of message: [UInt8],
        by publicKey: AgentPublicKey
    ) -> Bool {
        guard publicKey.algorithm == .ed25519,
              publicKey.rawRepresentation.count == 32,
              signature.rawRepresentation.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey.rawRepresentation)
        else {
            return false
        }
        return key.isValidSignature(signature.rawRepresentation, for: message)
    }
}
#endif
