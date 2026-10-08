//
//  ReleaseSource.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Where the Manager finds deployable releases — GitHub Releases, through the GitHub App.
///
/// Runs on the Manager, never on a host or a client: it is the side that holds GitHub credentials.
public protocol ReleaseSource: Sendable {

    /// Releases of a repository, newest first, with ``ReleaseInfo/eligibility`` worked out for
    /// one platform.
    ///
    /// - Parameters:
    ///   - repository: the repository, as `owner/name`.
    ///   - platform: the platform the releases would be deployed on.
    func releases(of repository: String, for platform: ArtifactPlatform) async throws -> [ReleaseInfo]
}
