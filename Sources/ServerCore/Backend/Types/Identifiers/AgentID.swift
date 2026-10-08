//
//  AgentID.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Identifies one enrolled agent, and therefore the key pair it signs with.
///
/// Distinct from ``ServerID`` because re-enrolling a host — after a reinstall or a revoked key —
/// creates a new agent identity for the same server.
public struct AgentID: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
