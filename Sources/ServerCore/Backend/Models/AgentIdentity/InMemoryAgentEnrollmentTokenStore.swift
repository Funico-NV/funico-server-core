//
//  InMemoryAgentEnrollmentTokenStore.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// An ``AgentEnrollmentTokenStore`` in process memory: redeeming removes the grant, so a token
/// works once.
///
/// Enough for a single Manager process, and for tests. A restart forgets every outstanding token,
/// which costs an administrator one re-issue and nothing else — a token lives fifteen minutes. It
/// keeps tokens in plain text, which is acceptable only because they never touch disk; a
/// persistent store should keep a hash.
public actor InMemoryAgentEnrollmentTokenStore: AgentEnrollmentTokenStore {

    private var grants: [AgentEnrollmentToken: AgentEnrollmentGrant] = [:]

    /// Creates an empty store.
    public init() {}

    /// The grants issued and not yet redeemed. Expired ones stay until someone presents them.
    public var outstanding: [AgentEnrollmentGrant] { Array(grants.values) }

    public func save(_ grant: AgentEnrollmentGrant) {
        grants[grant.token] = grant
    }

    public func redeem(_ token: AgentEnrollmentToken) -> AgentEnrollmentGrant? {
        grants.removeValue(forKey: token)
    }
}
