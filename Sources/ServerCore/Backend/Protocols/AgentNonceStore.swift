//
//  AgentNonceStore.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Remembers which challenges have already been answered, so each is accepted at most once.
///
/// ``AgentAuthenticator`` consumes a challenge's nonce before it checks the signature. A second
/// response to the same challenge — a replay of a captured frame, or a retry — finds the nonce
/// already used and is refused, whatever its signature.
///
/// Storage stays bounded: a nonce only needs remembering until its challenge expires, because after
/// that the expiry check refuses it first. ``InMemoryAgentNonceStore`` is enough for a single
/// Manager process; several Manager instances sharing agents need a shared store (a table with a
/// unique constraint on the nonce does it).
public protocol AgentNonceStore: Sendable {

    /// Marks a nonce as used, atomically.
    ///
    /// Two concurrent calls with the same nonce must not both return `true`; that atomicity is
    /// the whole of the replay guarantee.
    ///
    /// - Parameters:
    ///   - nonce: the challenge's nonce.
    ///   - expiresAt: when the challenge expires; the store may forget the nonce after this.
    ///   - now: the current time, for pruning.
    /// - Returns: `true` the first time a nonce is consumed, `false` every time after.
    func consume(_ nonce: AgentChallengeNonce, expiresAt: Date, now: Date) async throws -> Bool
}
