//
//  AgentPublicKey.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The public half of an agent's key pair: what the Manager stores at enrollment and verifies every
/// later challenge response against.
///
/// ```json
/// { "algorithm": "ed25519", "key": "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo" }
/// ```
///
/// The private half never leaves the host it was generated on and never appears in this package's
/// types; an ``AgentSigner`` holds it. Revoking an agent is deleting its public key on the Manager —
/// there is no shared secret to rotate on either side.
public struct AgentPublicKey: Sendable, Hashable, Codable, CustomStringConvertible {

    /// The scheme the key belongs to.
    public var algorithm: AgentKeyAlgorithm

    /// The key in its algorithm's raw form — for Ed25519, the 32 bytes RFC 8032 calls the public
    /// key. Encoded as unpadded base64url under `key`.
    public var rawRepresentation: [UInt8]

    /// Wraps a public key.
    ///
    /// Nothing is validated here; a malformed key is caught when the enrollment proof fails to
    /// verify against it, which is where an operator can see it.
    ///
    /// - Parameters:
    ///   - algorithm: the scheme the key belongs to.
    ///   - rawRepresentation: the key's bytes in that scheme's raw form.
    public init(algorithm: AgentKeyAlgorithm, rawRepresentation: [UInt8]) {
        self.algorithm = algorithm
        self.rawRepresentation = rawRepresentation
    }

    /// `algorithm:base64url`, for a log line. A public key is not a secret.
    public var description: String {
        "\(algorithm):\(Base64URL.encode(rawRepresentation))"
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm, key
    }

    /// Decodes a key; `key` must be non-empty unpadded base64url.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = try container.decode(AgentKeyAlgorithm.self, forKey: .algorithm)
        rawRepresentation = try Base64URL.decode(
            try container.decode(String.self, forKey: .key),
            in: container,
            forKey: .key
        )
    }

    /// Encodes a key.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encode(Base64URL.encode(rawRepresentation), forKey: .key)
    }
}
