//
//  AgentEvent.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Something the agent reports without being asked.
///
/// Encoded flat, with a `kind` discriminator. A kind this version does not know decodes as
/// ``unsupported(kind:)`` so that a newer agent never breaks an older Manager's connection.
public enum AgentEvent: Sendable, Hashable {

    /// A service's status changed — it crashed, systemd restarted it, someone stopped it on the
    /// host.
    case statusChanged(ServiceStatus)

    /// A periodic sample of the host's load.
    case resources(ServerResources)

    /// New entries from a log being followed with ``AgentCommand/followLogs(service:afterCursor:)``,
    /// oldest first.
    case logs([LogEntry])

    /// A deployment moved to a new state, including one the agent finished on its own while the
    /// Manager was unreachable.
    case deployment(DeploymentID, service: ServiceID, state: DeploymentState)

    /// A kind this version does not know. Never sent; only decoded.
    case unsupported(kind: String)
}

extension AgentEvent: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind, status, resources, entries, deployment, service, state
    }

    private enum Kind: String {
        case statusChanged, resources, logs, deployment
    }

    /// Decodes the flat form. An unknown `kind` becomes ``unsupported(kind:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)

        switch Kind(rawValue: rawKind) {
        case .statusChanged:
            self = .statusChanged(try container.decode(ServiceStatus.self, forKey: .status))
        case .resources:
            self = .resources(try container.decode(ServerResources.self, forKey: .resources))
        case .logs:
            self = .logs(try container.decode([LogEntry].self, forKey: .entries))
        case .deployment:
            self = .deployment(
                try container.decode(DeploymentID.self, forKey: .deployment),
                service: try container.decode(ServiceID.self, forKey: .service),
                state: try container.decode(DeploymentState.self, forKey: .state)
            )
        case nil:
            self = .unsupported(kind: rawKind)
        }
    }

    /// Encodes the flat form.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .statusChanged(let status):
            try container.encode(Kind.statusChanged.rawValue, forKey: .kind)
            try container.encode(status, forKey: .status)
        case .resources(let resources):
            try container.encode(Kind.resources.rawValue, forKey: .kind)
            try container.encode(resources, forKey: .resources)
        case .logs(let entries):
            try container.encode(Kind.logs.rawValue, forKey: .kind)
            try container.encode(entries, forKey: .entries)
        case .deployment(let deployment, let service, let state):
            try container.encode(Kind.deployment.rawValue, forKey: .kind)
            try container.encode(deployment, forKey: .deployment)
            try container.encode(service, forKey: .service)
            try container.encode(state, forKey: .state)
        case .unsupported(let kind):
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "\"\(kind)\" is a received event kind this version does not know; it cannot be sent"
                )
            )
        }
    }
}
