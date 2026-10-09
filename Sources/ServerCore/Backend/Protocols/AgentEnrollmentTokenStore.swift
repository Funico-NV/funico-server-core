//
//  AgentEnrollmentTokenStore.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Holds the enrollment tokens the Manager has issued and not yet seen redeemed.
///
/// ``AgentEnrollmentAuthority`` saves a grant when it issues a token and redeems it when an agent
/// presents it. Redeeming removes it, which is what makes a token single use.
///
/// A token is a bearer secret for the next fifteen minutes. A persistent implementation should store
/// a hash of ``AgentEnrollmentToken/rawValue`` and look up by hash, so a database dump does not hand
/// out enrollments. ``InMemoryAgentEnrollmentTokenStore`` is enough for a single Manager process.
public protocol AgentEnrollmentTokenStore: Sendable {

    /// Stores a newly issued grant.
    ///
    /// - Parameter grant: the token and the server it enrolls.
    func save(_ grant: AgentEnrollmentGrant) async throws

    /// Removes the grant for `token` and returns it, atomically.
    ///
    /// Two concurrent calls with the same token must not both receive the grant. Expired grants
    /// are returned like any other — the authority checks expiry — and are removed all the same.
    ///
    /// - Parameter token: the token an agent presented.
    /// - Returns: the grant, or `nil` if the token was never issued or has already been redeemed.
    func redeem(_ token: AgentEnrollmentToken) async throws -> AgentEnrollmentGrant?
}
