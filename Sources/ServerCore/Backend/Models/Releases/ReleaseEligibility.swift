//
//  ReleaseEligibility.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Whether a release may be deployed, and if not, the first reason why.
///
/// Computed by the Manager when it lists releases, so the app can grey out the Deploy button with
/// a reason instead of letting the agent refuse later. The agent still checks everything itself.
public enum ReleaseEligibility: String, Sendable, Hashable, Codable, CaseIterable {

    /// Published, stable, and carries a verifiable artifact for the host's platform.
    case eligible

    /// Not published yet.
    case draft

    /// Marked as a prerelease, and the service has not opted into prereleases.
    case prerelease

    /// Has no artifact at all — a tag-only release, or one from before artifacts were built.
    case noArtifact

    /// Has artifacts, but none for the host's platform.
    case incompatiblePlatform

    /// Has an artifact for the platform but is missing its checksum or signature, so it cannot be
    /// verified and will not be installed.
    case unverifiable

    /// Whether the release may be deployed.
    public var isEligible: Bool { self == .eligible }
}
