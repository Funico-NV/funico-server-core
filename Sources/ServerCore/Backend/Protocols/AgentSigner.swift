//
//  AgentSigner.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Holds an agent's private key and signs with it. Implemented on the agent's host.
///
/// `ServerCore` has no cryptography of its own — it has zero package dependencies, and that is what
/// keeps it importable from an iOS target. The protocol is the seam: `ServerCoreCrypto` provides
/// `Ed25519AgentSigner` (swift-crypto, behind the `Crypto` trait), and `ServerCoreTesting`
/// provides `MockAgentSigner` for tests that should not need either.
///
/// An implementation never exposes the private key through this protocol, and the agent never sends
/// it anywhere: generated on the host, stored `0600`, used only here.
public protocol AgentSigner: Sendable {

    /// The public half of the key this signer signs with, as the Manager will store it.
    var publicKey: AgentPublicKey { get }

    /// Signs bytes built by ``AgentSigningPayload`` — never anything else. A signer that will sign
    /// arbitrary input is a signing oracle; every caller in this package passes a domain-separated
    /// payload.
    ///
    /// Async and throwing so an implementation may keep its key in a keychain or hardware token.
    ///
    /// - Parameter message: the canonical payload.
    /// - Returns: the signature.
    func sign(_ message: [UInt8]) async throws -> AgentSignature
}
