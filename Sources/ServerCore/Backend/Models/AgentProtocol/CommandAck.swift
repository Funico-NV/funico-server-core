//
//  CommandAck.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The agent's immediate answer to a command: accepted and queued, or refused.
///
/// Sent as soon as the command is decoded and checked, before any work starts, so the Manager can
/// tell "the agent has it" from "the agent never got it" — the difference between waiting and
/// re-sending.
public struct CommandAck: Sendable, Hashable, Codable {

    /// The command this answers.
    public var command: CommandID

    /// Why it was refused. `nil` means accepted.
    public var error: ServerCoreError?

    /// Whether the command was accepted.
    public var isAccepted: Bool { error == nil }

    /// Creates an acknowledgement.
    ///
    /// - Parameters:
    ///   - command: the command this answers.
    ///   - error: why it was refused, or `nil` if it was accepted.
    public init(command: CommandID, error: ServerCoreError? = nil) {
        self.command = command
        self.error = error
    }
}
