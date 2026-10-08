//
//  CommandEnvelope.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One command from the Manager, with what the agent needs to run it exactly once and on time.
public struct CommandEnvelope: Sendable, Hashable, Codable, Identifiable {

    /// The command's identity. Re-sending an envelope with the same ID returns the stored result
    /// instead of running it again; see ``CommandID``.
    public var id: CommandID

    /// When the Manager issued it.
    public var issuedAt: Date

    /// The latest time the agent may *start* it. A command still queued at its deadline is
    /// answered with ``ServerCoreError/Code/deadlineExceeded`` and not run — a restart someone
    /// asked for ten minutes ago, before a long outage, is no longer what they want.
    public var deadline: Date?

    /// The subject of the person who asked, as Funico Authentication identifies them, for the
    /// host's own audit log.
    public var issuedBy: String

    /// What to do.
    public var command: AgentCommand

    /// Creates an envelope.
    ///
    /// - Parameters:
    ///   - id: the command's identity; a fresh one by default.
    ///   - issuedAt: when the Manager issued it.
    ///   - deadline: the latest time the agent may start it.
    ///   - issuedBy: the subject of the person who asked.
    ///   - command: what to do.
    public init(
        id: CommandID = CommandID(),
        issuedAt: Date = Date(),
        deadline: Date? = nil,
        issuedBy: String,
        command: AgentCommand
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.deadline = deadline
        self.issuedBy = issuedBy
        self.command = command
    }

    /// Whether the deadline has passed at `date`.
    ///
    /// - Parameter date: the time to check against; now by default.
    public func isExpired(at date: Date = Date()) -> Bool {
        deadline.map { date > $0 } ?? false
    }
}
