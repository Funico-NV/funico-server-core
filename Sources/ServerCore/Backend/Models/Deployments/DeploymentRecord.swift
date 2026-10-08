//
//  DeploymentRecord.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The history entry for one deployment: who asked, what moved to what, and how it ended.
public struct DeploymentRecord: Sendable, Hashable, Codable, Identifiable {

    /// The deployment.
    public var id: DeploymentID

    /// The host it ran on.
    public var server: ServerID

    /// The service deployed.
    public var service: ServiceID

    /// The version running before, if known.
    public var fromVersion: String?

    /// The version being deployed.
    public var toVersion: String

    /// The subject of the person who requested it, as Funico Authentication identifies them.
    public var requestedBy: String

    /// When it was requested.
    public var requestedAt: Date

    /// When ``state`` last changed.
    public var updatedAt: Date

    /// Where it is, or how it ended.
    public var state: DeploymentState

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - id: the deployment.
    ///   - server: the host it ran on.
    ///   - service: the service deployed.
    ///   - fromVersion: the version running before.
    ///   - toVersion: the version being deployed.
    ///   - requestedBy: the subject of the person who requested it.
    ///   - requestedAt: when it was requested.
    ///   - updatedAt: when `state` last changed.
    ///   - state: where it is, or how it ended.
    public init(
        id: DeploymentID,
        server: ServerID,
        service: ServiceID,
        fromVersion: String? = nil,
        toVersion: String,
        requestedBy: String,
        requestedAt: Date,
        updatedAt: Date,
        state: DeploymentState
    ) {
        self.id = id
        self.server = server
        self.service = service
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.requestedBy = requestedBy
        self.requestedAt = requestedAt
        self.updatedAt = updatedAt
        self.state = state
    }
}
