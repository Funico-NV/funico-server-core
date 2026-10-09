//
//  AgentEnrollmentGrant.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// An issued, unredeemed enrollment token and what it entitles its bearer to: enrolling one agent
/// for one server, until it expires.
///
/// The Manager creates one with ``AgentEnrollmentAuthority/issueToken(for:now:)``, shows
/// ``token`` to the administrator once, and keeps the grant in its ``AgentEnrollmentTokenStore``.
public struct AgentEnrollmentGrant: Sendable, Hashable, Codable {

    /// The secret the operator carries to the host.
    public var token: AgentEnrollmentToken

    /// The server the enrolled agent will speak for. Decided by the administrator who issued the
    /// token, never by the agent.
    public var server: ServerID

    /// After this, the token is refused even if it was never used.
    public var expiresAt: Date

    /// Creates a grant.
    ///
    /// - Parameters:
    ///   - token: the secret.
    ///   - server: the server it enrolls an agent for.
    ///   - expiresAt: when it stops being accepted.
    public init(token: AgentEnrollmentToken, server: ServerID, expiresAt: Date) {
        self.token = token
        self.server = server
        self.expiresAt = expiresAt
    }
}
