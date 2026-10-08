//
//  AgentCommand.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Everything the Manager can ask an agent to do.
///
/// This list *is* the agent's attack surface, so it is deliberately short and every case names a
/// service by ``ServiceID`` only. There is no case that carries a command line, a unit name or a
/// path, and there must never be one: a compromised Manager can then at worst start, stop and
/// restart services the host lists, read their logs, and deploy builds that pass signature
/// verification.
///
/// A command kind this version does not know decodes as ``unsupported(kind:)``, which the agent
/// rejects with ``ServerCoreError/Code/unsupportedCommand``. Failing to decode instead would leave
/// the agent unable to tell the Manager *which* command it refused.
///
/// Encoded flat, with a `kind` discriminator:
///
/// ```json
/// { "kind": "perform", "service": "invoices", "operation": "restart" }
/// ```
public enum AgentCommand: Sendable, Hashable {

    /// Describe every service the host lists. Answered with ``CommandResult/services``.
    case listServices

    /// Report the status of one service, or of every listed service when `service` is `nil`.
    /// Answered with ``CommandResult/statuses``.
    case status(service: ServiceID?)

    /// Start, stop or restart a service.
    case perform(ServiceOperation, service: ServiceID)

    /// Read a page of a service's log. Answered with ``CommandResult/logs``.
    case queryLogs(service: ServiceID, query: LogQuery)

    /// Stream a service's new log entries as ``AgentEvent/logs(_:)`` events, starting after
    /// `afterCursor`, or from now when it is `nil`. Continues until
    /// ``stopFollowingLogs(service:)`` or the connection drops; a reconnect does not resume it.
    case followLogs(service: ServiceID, afterCursor: String?)

    /// Stop streaming a service's log.
    case stopFollowingLogs(service: ServiceID)

    /// Install and activate a release. Progress arrives as ``CommandProgress``, and the outcome
    /// as ``CommandResult/deployment``.
    case deploy(DeploymentRequest)

    /// Restore the release that was live before the current one, as a new deployment with its own
    /// ID.
    case rollback(service: ServiceID, deployment: DeploymentID)

    /// Cancel a command that has not started yet, or a deployment that has not reached
    /// ``DeploymentStage/activating``. Refused otherwise: stopping halfway through an activation is
    /// what a rollback is for.
    case cancel(CommandID)

    /// A kind this version does not know. Never sent; only decoded.
    case unsupported(kind: String)

    /// The service the command is about, if it is about one. The agent serialises commands per
    /// service using this.
    public var service: ServiceID? {
        switch self {
        case .status(let service): service
        case .perform(_, let service),
             .queryLogs(let service, _),
             .followLogs(let service, _),
             .stopFollowingLogs(let service),
             .rollback(let service, _):
            service
        case .deploy(let request): request.service
        case .listServices, .cancel, .unsupported: nil
        }
    }
}

extension AgentCommand: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind, service, operation, query, afterCursor, request, deployment, command
    }

    private enum Kind: String {
        case listServices, status, perform, queryLogs, followLogs, stopFollowingLogs, deploy, rollback, cancel
    }

    /// Decodes the flat form. An unknown `kind` becomes ``unsupported(kind:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)

        guard let kind = Kind(rawValue: rawKind) else {
            self = .unsupported(kind: rawKind)
            return
        }

        switch kind {
        case .listServices:
            self = .listServices
        case .status:
            self = .status(service: try container.decodeIfPresent(ServiceID.self, forKey: .service))
        case .perform:
            self = .perform(
                try container.decode(ServiceOperation.self, forKey: .operation),
                service: try container.decode(ServiceID.self, forKey: .service)
            )
        case .queryLogs:
            self = .queryLogs(
                service: try container.decode(ServiceID.self, forKey: .service),
                query: try container.decodeIfPresent(LogQuery.self, forKey: .query) ?? LogQuery()
            )
        case .followLogs:
            self = .followLogs(
                service: try container.decode(ServiceID.self, forKey: .service),
                afterCursor: try container.decodeIfPresent(String.self, forKey: .afterCursor)
            )
        case .stopFollowingLogs:
            self = .stopFollowingLogs(service: try container.decode(ServiceID.self, forKey: .service))
        case .deploy:
            self = .deploy(try container.decode(DeploymentRequest.self, forKey: .request))
        case .rollback:
            self = .rollback(
                service: try container.decode(ServiceID.self, forKey: .service),
                deployment: try container.decode(DeploymentID.self, forKey: .deployment)
            )
        case .cancel:
            self = .cancel(try container.decode(CommandID.self, forKey: .command))
        }
    }

    /// Encodes the flat form.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .listServices:
            try container.encode(Kind.listServices.rawValue, forKey: .kind)
        case .status(let service):
            try container.encode(Kind.status.rawValue, forKey: .kind)
            try container.encodeIfPresent(service, forKey: .service)
        case .perform(let operation, let service):
            try container.encode(Kind.perform.rawValue, forKey: .kind)
            try container.encode(operation, forKey: .operation)
            try container.encode(service, forKey: .service)
        case .queryLogs(let service, let query):
            try container.encode(Kind.queryLogs.rawValue, forKey: .kind)
            try container.encode(service, forKey: .service)
            try container.encode(query, forKey: .query)
        case .followLogs(let service, let afterCursor):
            try container.encode(Kind.followLogs.rawValue, forKey: .kind)
            try container.encode(service, forKey: .service)
            try container.encodeIfPresent(afterCursor, forKey: .afterCursor)
        case .stopFollowingLogs(let service):
            try container.encode(Kind.stopFollowingLogs.rawValue, forKey: .kind)
            try container.encode(service, forKey: .service)
        case .deploy(let request):
            try container.encode(Kind.deploy.rawValue, forKey: .kind)
            try container.encode(request, forKey: .request)
        case .rollback(let service, let deployment):
            try container.encode(Kind.rollback.rawValue, forKey: .kind)
            try container.encode(service, forKey: .service)
            try container.encode(deployment, forKey: .deployment)
        case .cancel(let command):
            try container.encode(Kind.cancel.rawValue, forKey: .kind)
            try container.encode(command, forKey: .command)
        case .unsupported(let kind):
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "\"\(kind)\" is a received command kind this version does not know; it cannot be sent"
                )
            )
        }
    }
}
