//
//  AgentChallengeNonce.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The random value that makes each ``AgentChallenge`` unique, and so each signature over one
/// useless for any other connection.
///
/// Encoded as a bare unpadded base64url string.
public struct AgentChallengeNonce: Sendable, Hashable, Codable {

    /// How many random bytes ``random()`` draws: 256 bits, so a nonce can be neither guessed nor
    /// repeated by chance in the lifetime of any deployment.
    public static let byteCount = 32

    /// The nonce's bytes.
    public var rawRepresentation: [UInt8]

    /// Wraps existing bytes, for decoding and for tests. Issue new nonces with ``random()``.
    ///
    /// - Parameter rawRepresentation: the nonce's bytes.
    public init(rawRepresentation: [UInt8]) {
        self.rawRepresentation = rawRepresentation
    }

    /// A fresh nonce of ``byteCount`` bytes from the system's cryptographically secure generator.
    public static func random() -> AgentChallengeNonce {
        AgentChallengeNonce(rawRepresentation: Base64URL.randomBytes(byteCount))
    }

    /// Decodes a non-empty unpadded base64url string.
    public init(from decoder: any Decoder) throws {
        rawRepresentation = try Base64URL.decode(from: decoder)
    }

    /// Encodes as unpadded base64url.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Base64URL.encode(rawRepresentation))
    }
}

extension AgentChallengeNonce: CustomStringConvertible {

    /// The base64url form. A nonce is public; it is only ever useful once.
    public var description: String { Base64URL.encode(rawRepresentation) }
}
