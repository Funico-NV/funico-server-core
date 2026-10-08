//
//  CommandResult.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// How a command ended. Exactly one per accepted command, and the same one again if the command is
/// re-sent.
///
/// One flat type with optional payloads rather than an enum per command kind, so any client —
/// including a browser — reads it without knowing Swift's enum encoding, and so a payload added
/// later is simply a new optional field older readers ignore. Which payload is set follows from
/// the command:
///
/// | Command | Payload |
/// |---|---|
/// | ``AgentCommand/listServices`` | ``services`` |
/// | ``AgentCommand/status(service:)``, ``AgentCommand/perform(_:service:)`` | ``statuses`` |
/// | ``AgentCommand/queryLogs(service:query:)`` | ``logs`` |
/// | ``AgentCommand/deploy(_:)``, ``AgentCommand/rollback(service:deployment:)`` | ``deployment`` |
public struct CommandResult: Sendable, Hashable, Codable {

    /// The command this ends.
    public var command: CommandID

    /// When the agent finished it.
    public var completedAt: Date

    /// Why it failed. `nil` means it succeeded.
    public var error: ServerCoreError?

    /// The services the host lists.
    public var services: [ServiceDescriptor]?

    /// Service statuses: those asked for, or, after an operation, the service's new status.
    public var statuses: [ServiceStatus]?

    /// A page of log entries, oldest first.
    public var logs: [LogEntry]?

    /// How a deployment or rollback ended. Set even when ``error`` is, so a failed deployment
    /// still says whether it was rolled back.
    public var deployment: DeploymentState?

    /// Whether the command succeeded.
    public var isSuccess: Bool { error == nil }

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - command: the command this ends.
    ///   - completedAt: when the agent finished it.
    ///   - error: why it failed, or `nil`.
    ///   - services: the services the host lists.
    ///   - statuses: service statuses.
    ///   - logs: a page of log entries.
    ///   - deployment: how a deployment or rollback ended.
    public init(
        command: CommandID,
        completedAt: Date = Date(),
        error: ServerCoreError? = nil,
        services: [ServiceDescriptor]? = nil,
        statuses: [ServiceStatus]? = nil,
        logs: [LogEntry]? = nil,
        deployment: DeploymentState? = nil
    ) {
        self.command = command
        self.completedAt = completedAt
        self.error = error
        self.services = services
        self.statuses = statuses
        self.logs = logs
        self.deployment = deployment
    }
}
