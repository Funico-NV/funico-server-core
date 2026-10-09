//
//  AgentSignature.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// A signature an ``AgentSigner`` made over one of the payloads ``AgentSigningPayload`` describes.
///
/// Encoded as a bare unpadded base64url string. It carries no algorithm of its own: it is only ever
/// checked against the key the Manager stored at enrollment, and that key names the algorithm.
public struct AgentSignature: Sendable, Hashable, Codable {

    /// The signature in its algorithm's raw form — 64 bytes for Ed25519.
    public var rawRepresentation: [UInt8]

    /// Wraps signature bytes.
    ///
    /// - Parameter rawRepresentation: the signature in its algorithm's raw form.
    public init(rawRepresentation: [UInt8]) {
        self.rawRepresentation = rawRepresentation
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
