//
//  AgentSignatureVerifier.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Checks a signature against an enrolled agent's public key. Implemented on the Manager.
///
/// The counterpart of ``AgentSigner``, and behind a protocol for the same reason: `ServerCore`
/// stays free of package dependencies. `ServerCoreCrypto` provides `Ed25519AgentSignatureVerifier`;
/// `ServerCoreTesting` provides `MockAgentSignatureVerifier`.
public protocol AgentSignatureVerifier: Sendable {

    /// Whether `signature` is a valid signature of `message` by the private key matching
    /// `publicKey`.
    ///
    /// Never throws: a key of an algorithm this verifier does not implement, a key or signature of
    /// the wrong length, and a signature that simply does not match are all `false`. The caller
    /// has one decision to make, and an error would only tempt it to treat some failures as
    /// softer than others.
    ///
    /// - Parameters:
    ///   - signature: the signature to check.
    ///   - message: the canonical payload the signer should have signed.
    ///   - publicKey: the key the Manager stored at enrollment.
    func isValidSignature(
        _ signature: AgentSignature,
        of message: [UInt8],
        by publicKey: AgentPublicKey
    ) -> Bool
}
