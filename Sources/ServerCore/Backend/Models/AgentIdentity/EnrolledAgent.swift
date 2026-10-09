//
//  EnrolledAgent.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The Manager's record of an enrolled agent: the identity, the server it speaks for, and the key
/// every challenge response must verify against.
///
/// ``AgentEnrollmentAuthority/enroll(_:now:)`` returns one; the Manager persists it and passes it to
/// ``AgentAuthenticator/verify(_:to:from:now:)`` on each connection. Revoking an agent is deleting
/// this record — with no key to verify against, it cannot authenticate again, and there is no
/// shared secret to rotate anywhere.
public struct EnrolledAgent: Sendable, Hashable, Codable {

    /// The agent's identity.
    public var agent: AgentID

    /// The server it speaks for.
    public var server: ServerID

    /// The public key it enrolled with.
    public var publicKey: AgentPublicKey

    /// When it enrolled.
    public var enrolledAt: Date

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - agent: the agent's identity.
    ///   - server: the server it speaks for.
    ///   - publicKey: the key it enrolled with.
    ///   - enrolledAt: when it enrolled.
    public init(agent: AgentID, server: ServerID, publicKey: AgentPublicKey, enrolledAt: Date) {
        self.agent = agent
        self.server = server
        self.publicKey = publicKey
        self.enrolledAt = enrolledAt
    }
}
