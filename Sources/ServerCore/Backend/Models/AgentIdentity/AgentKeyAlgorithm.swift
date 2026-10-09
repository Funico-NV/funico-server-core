//
//  AgentKeyAlgorithm.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The signature scheme an ``AgentPublicKey`` belongs to.
///
/// Every key on the wire names its algorithm, so a second scheme can be introduced later — a
/// hardware-backed key, say — without guessing from a key's length. A verifier refuses any
/// algorithm it does not implement rather than trying to interpret the bytes.
///
/// Open, like every vocabulary in this package: an older Manager decodes a newer agent's key and
/// then refuses it, instead of failing to read the request at all.
public struct AgentKeyAlgorithm: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Ed25519 (RFC 8032): a 32-byte public key and a 64-byte signature. The only algorithm agents
    /// use today, implemented in `ServerCoreCrypto`.
    public static let ed25519 = AgentKeyAlgorithm("ed25519")
}
