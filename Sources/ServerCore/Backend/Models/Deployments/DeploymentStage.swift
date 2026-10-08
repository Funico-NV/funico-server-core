//
//  DeploymentStage.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One step of putting a release into production on a host, in the order they happen.
///
/// The order is the point. Everything before ``activating`` happens beside production — in a
/// staging directory, a `.partial` release directory — so a failure there leaves the running
/// service exactly as it was. From ``activating`` on, production has been touched, and a failure
/// means rolling back. ``touchesProduction`` is that line, and it decides what an agent does when
/// it restarts mid-deployment.
public enum DeploymentStage: String, Sendable, Hashable, Codable, CaseIterable, Comparable {

    /// The Manager has asked; the agent has not acknowledged yet.
    case requested

    /// The agent has accepted the command and queued it behind any other command for the service.
    case accepted

    /// Fetching the archive, checksum and signature into a staging directory. Resumable.
    case downloading

    /// Checking the checksum, the signature and the manifest.
    case verifying

    /// Unpacking into `releases/<version>.partial`, hashing every file, then renaming it.
    case extracting

    /// Checking the environment file has every required key, there is disk space, and the
    /// entrypoint is executable. The last stage that cannot affect production.
    case preflight

    /// Swapping the `current` symlink to the new release. Production is touched from here on.
    case activating

    /// Restarting the service on the new release.
    case restarting

    /// Waiting for the service to stay up and answer its health check with the new version.
    case checkingReadiness

    /// Done: the new release is live, older releases are pruned.
    case committed

    /// Whether a failure at this stage means the running service may already be affected, and so
    /// must be rolled back rather than simply abandoned.
    public var touchesProduction: Bool {
        self >= .activating
    }

    public static func < (lhs: DeploymentStage, rhs: DeploymentStage) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    private var ordinal: Int {
        Self.allCases.firstIndex(of: self)!
    }
}
