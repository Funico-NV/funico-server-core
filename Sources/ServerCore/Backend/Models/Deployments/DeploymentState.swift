//
//  DeploymentState.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Where a deployment is, and how it ended.
///
/// The terminal states distinguish *what the host is now running*, which is what an operator needs
/// to know:
///
/// | State | Production is running |
/// |---|---|
/// | ``succeeded`` | the new release |
/// | ``failed(at:error:)`` before activation, or ``cancelled`` | the old release, untouched |
/// | ``rolledBack(from:error:)`` | the old release, restarted |
/// | ``rollbackFailed(from:error:)`` | unknown — a person must look |
///
/// Nothing after ``rollbackFailed(from:error:)`` is automatic. A host that could not restore its
/// previous release is exactly the situation where another automated attempt does more harm.
///
/// Encoded flat — `{"status": "failed", "stage": "verifying", "error": {…}}` — so a browser can
/// read it without knowing Swift's enum encoding.
public enum DeploymentState: Sendable, Hashable {

    /// Waiting for the agent, or queued behind another command for the same service.
    case pending

    /// Underway at the given stage.
    case running(DeploymentStage)

    /// The new release is live and ready.
    case succeeded

    /// Stopped at a stage. If that stage is before ``DeploymentStage/activating``, production was
    /// never touched. A failure at a later stage becomes ``rolledBack(from:error:)`` or
    /// ``rollbackFailed(from:error:)`` instead, so in practice this names an early stage.
    case failed(at: DeploymentStage, error: ServerCoreError)

    /// Cancelled before activation. Production was never touched; cancellation is refused after.
    case cancelled

    /// Failed at or after activation, and the previous release was restored and passed its
    /// readiness check.
    case rolledBack(from: DeploymentStage, error: ServerCoreError)

    /// Failed at or after activation, and restoring the previous release failed too.
    case rollbackFailed(from: DeploymentStage, error: ServerCoreError)

    /// Whether the deployment has ended. A terminal state never changes again.
    public var isTerminal: Bool {
        switch self {
        case .pending, .running: false
        case .succeeded, .failed, .cancelled, .rolledBack, .rollbackFailed: true
        }
    }

    /// The error that ended the deployment, if it ended badly.
    public var error: ServerCoreError? {
        switch self {
        case .failed(_, let error), .rolledBack(_, let error), .rollbackFailed(_, let error): error
        case .pending, .running, .succeeded, .cancelled: nil
        }
    }
}

extension DeploymentState: Codable {

    private enum CodingKeys: String, CodingKey {
        case status, stage, error
    }

    private enum Status: String, Codable {
        case pending, running, succeeded, failed, cancelled, rolledBack, rollbackFailed
    }

    /// Decodes the flat form.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Status.self, forKey: .status) {
        case .pending:
            self = .pending
        case .running:
            self = .running(try container.decode(DeploymentStage.self, forKey: .stage))
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed(
                at: try container.decode(DeploymentStage.self, forKey: .stage),
                error: try container.decode(ServerCoreError.self, forKey: .error)
            )
        case .cancelled:
            self = .cancelled
        case .rolledBack:
            self = .rolledBack(
                from: try container.decode(DeploymentStage.self, forKey: .stage),
                error: try container.decode(ServerCoreError.self, forKey: .error)
            )
        case .rollbackFailed:
            self = .rollbackFailed(
                from: try container.decode(DeploymentStage.self, forKey: .stage),
                error: try container.decode(ServerCoreError.self, forKey: .error)
            )
        }
    }

    /// Encodes the flat form.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:
            try container.encode(Status.pending, forKey: .status)
        case .running(let stage):
            try container.encode(Status.running, forKey: .status)
            try container.encode(stage, forKey: .stage)
        case .succeeded:
            try container.encode(Status.succeeded, forKey: .status)
        case .failed(let stage, let error):
            try container.encode(Status.failed, forKey: .status)
            try container.encode(stage, forKey: .stage)
            try container.encode(error, forKey: .error)
        case .cancelled:
            try container.encode(Status.cancelled, forKey: .status)
        case .rolledBack(let stage, let error):
            try container.encode(Status.rolledBack, forKey: .status)
            try container.encode(stage, forKey: .stage)
            try container.encode(error, forKey: .error)
        case .rollbackFailed(let stage, let error):
            try container.encode(Status.rollbackFailed, forKey: .status)
            try container.encode(stage, forKey: .stage)
            try container.encode(error, forKey: .error)
        }
    }
}
