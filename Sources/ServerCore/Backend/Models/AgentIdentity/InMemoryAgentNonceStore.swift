//
//  InMemoryAgentNonceStore.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// An ``AgentNonceStore`` in process memory: correct for a single Manager process.
///
/// Every nonce is kept until its challenge expires and pruned on the next call after that, so
/// memory is bounded by the number of challenges issued in one challenge lifetime. Forgetting on
/// restart is safe for the same reason: any challenge issued before the restart is either expired
/// or belonged to a connection the restart closed.
///
/// Not enough for several Manager instances sharing agents — each would accept a response once.
/// Back the protocol with shared storage for that.
public actor InMemoryAgentNonceStore: AgentNonceStore {

    private var used: [AgentChallengeNonce: Date] = [:]

    /// Creates an empty store.
    public init() {}

    /// How many nonces are remembered right now. For tests and diagnostics.
    public var count: Int { used.count }

    public func consume(_ nonce: AgentChallengeNonce, expiresAt: Date, now: Date) -> Bool {
        used = used.filter { $0.value > now }
        guard used[nonce] == nil else { return false }
        used[nonce] = expiresAt
        return true
    }
}
