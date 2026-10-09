//
//  AgentEnrollmentRequest.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// What an agent sends to enroll: the operator's token, its freshly generated public key, and proof
/// that it holds the matching private key.
///
/// ```json
/// { "token": "fnc-enroll-…", "publicKey": { "algorithm": "ed25519", "key": "…" }, "proof": "…" }
/// ```
///
/// ``proof`` is a signature over ``signingBytes(token:publicKey:)``. It costs the agent one
/// signature and buys two things: a key that was mangled in transit or cannot sign is rejected at
/// enrollment, where the operator is watching, instead of at every connection afterwards; and the
/// token is bound to this key, so the request cannot be re-pointed at a different key without
/// the private half of that key.
public struct AgentEnrollmentRequest: Sendable, Hashable, Codable {

    /// The one-time token the operator was given.
    public var token: AgentEnrollmentToken

    /// The public key to bind to the new ``AgentID``.
    public var publicKey: AgentPublicKey

    /// A signature by ``publicKey`` over ``signingBytes(token:publicKey:)``.
    public var proof: AgentSignature

    /// Wraps already-signed fields, for decoding and tests. An agent uses
    /// ``init(token:signer:)``.
    ///
    /// - Parameters:
    ///   - token: the one-time token.
    ///   - publicKey: the key to enroll.
    ///   - proof: the proof-of-possession signature.
    public init(token: AgentEnrollmentToken, publicKey: AgentPublicKey, proof: AgentSignature) {
        self.token = token
        self.publicKey = publicKey
        self.proof = proof
    }

    /// Builds a request from a token and the agent's signer, signing the proof.
    ///
    /// - Parameters:
    ///   - token: the one-time token the operator was given.
    ///   - signer: the agent's key.
    public init(token: AgentEnrollmentToken, signer: any AgentSigner) async throws {
        let publicKey = signer.publicKey
        self.init(
            token: token,
            publicKey: publicKey,
            proof: try await signer.sign(Self.signingBytes(token: token, publicKey: publicKey))
        )
    }

    /// The bytes ``proof`` signs:
    /// `field(enrollmentContext) ‖ field(token) ‖ field(algorithm) ‖ field(key)`, in the layout
    /// ``AgentSigningPayload`` describes.
    ///
    /// - Parameters:
    ///   - token: the enrollment token.
    ///   - publicKey: the key being enrolled.
    /// - Returns: the canonical payload.
    public static func signingBytes(token: AgentEnrollmentToken, publicKey: AgentPublicKey) -> [UInt8] {
        var writer = CanonicalWriter(context: AgentSigningPayload.enrollmentContext)
        writer.append(token.rawValue)
        writer.append(publicKey.algorithm.rawValue)
        writer.append(publicKey.rawRepresentation)
        return writer.bytes
    }
}
