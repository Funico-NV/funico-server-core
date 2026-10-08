//
//  DeploymentRequest.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// What the Manager sends an agent to deploy one release of one service.
///
/// It names the service by ``ServiceID`` and the build by URL. Where the release goes, which unit
/// restarts and which key verifies it all come from the host's own allow-list, never from here.
public struct DeploymentRequest: Sendable, Hashable, Codable {

    /// The deployment this request belongs to. Reused on a retry.
    public var deployment: DeploymentID

    /// The service to deploy.
    public var service: ServiceID

    /// The version expected inside the artifact's manifest. A manifest declaring anything else is
    /// rejected, so a mislabelled asset cannot be installed under the wrong version.
    public var version: String

    /// The build to install.
    public var artifact: ReleaseArtifact

    /// Set when an administrator has confirmed a release whose manifest says
    /// ``ArtifactManifest/requiresMigration``. Without it the agent refuses such a release.
    public var migrationConfirmed: Bool

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - deployment: the deployment this request belongs to.
    ///   - service: the service to deploy.
    ///   - version: the version expected in the manifest.
    ///   - artifact: the build to install.
    ///   - migrationConfirmed: whether an administrator confirmed a migrating release.
    public init(
        deployment: DeploymentID,
        service: ServiceID,
        version: String,
        artifact: ReleaseArtifact,
        migrationConfirmed: Bool = false
    ) {
        self.deployment = deployment
        self.service = service
        self.version = version
        self.artifact = artifact
        self.migrationConfirmed = migrationConfirmed
    }
}
