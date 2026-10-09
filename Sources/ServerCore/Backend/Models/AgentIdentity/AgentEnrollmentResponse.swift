//
//  AgentEnrollmentResponse.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// What the Manager answers a successful enrollment with. The agent stores all three values
/// alongside its private key.
///
/// ```json
/// { "agent": "6f1c…", "server": "box-1", "manager": "manager.funico.internal" }
/// ```
public struct AgentEnrollmentResponse: Sendable, Hashable, Codable {

    /// The agent's new identity. It names itself with this on every connection.
    public var agent: AgentID

    /// The server the administrator enrolled it for.
    public var server: ServerID

    /// The Manager that enrolled it. The agent signs only challenges whose
    /// ``AgentChallenge/audience`` is this value.
    public var manager: ManagerID

    /// Creates a response.
    ///
    /// - Parameters:
    ///   - agent: the new agent identity.
    ///   - server: the server it speaks for.
    ///   - manager: the Manager it enrolled with.
    public init(agent: AgentID, server: ServerID, manager: ManagerID) {
        self.agent = agent
        self.server = server
        self.manager = manager
    }
}
