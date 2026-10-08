//
//  CommandProgress.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// An update on a long-running command, between its ``CommandAck`` and its ``CommandResult``.
///
/// Advisory: progress may be dropped or arrive late, and nothing may depend on seeing every one.
/// The ``CommandResult`` is the only authoritative outcome.
public struct CommandProgress: Sendable, Hashable, Codable {

    /// The command this is about.
    public var command: CommandID

    /// The deployment stage reached, for a deploy or rollback.
    public var stage: DeploymentStage?

    /// How far through the current step, from `0` to `1`, when that is knowable — a download.
    public var fractionCompleted: Double?

    /// A line for an operator to read.
    public var message: String?

    /// Creates a progress update.
    ///
    /// - Parameters:
    ///   - command: the command this is about.
    ///   - stage: the deployment stage reached.
    ///   - fractionCompleted: how far through the current step.
    ///   - message: a line for an operator to read.
    public init(
        command: CommandID,
        stage: DeploymentStage? = nil,
        fractionCompleted: Double? = nil,
        message: String? = nil
    ) {
        self.command = command
        self.stage = stage
        self.fractionCompleted = fractionCompleted
        self.message = message
    }
}
