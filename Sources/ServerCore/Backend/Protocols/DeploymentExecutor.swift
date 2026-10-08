//
//  DeploymentExecutor.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One way of installing a release on a host, split at the line where production is touched.
///
/// The agent drives a deployment through an executor in this order, writing each transition to
/// its journal *before* acting so it can recover after a crash:
///
/// 1. ``stage(_:progress:)`` — download, verify, extract, preflight. Production untouched; on
///    failure, ``discard(_:)`` and stop.
/// 2. ``activate(_:)`` — point `current` at the new release.
/// 3. Restart the service through ``ServiceBackend``.
/// 4. Wait on a ``HealthProbe``.
///
/// A failure in steps 2–4 is answered with ``rollback(_:)``. The executor never restarts the
/// service itself: restarts belong to the backend, so the same executor works under systemd and
/// under the process supervisor.
public protocol DeploymentExecutor: Sendable {

    /// Prepares a release beside the running one, and checks everything that can be checked
    /// without touching production.
    ///
    /// Must verify the archive's checksum and signature against the key pinned for the service on
    /// the host, call ``ArtifactManifest/validate()``, and check that the manifest's service,
    /// version and platform match the request and the host. Must refuse a manifest that
    /// ``ArtifactManifest/requiresMigration`` unless ``DeploymentRequest/migrationConfirmed``.
    ///
    /// - Parameters:
    ///   - request: what to deploy.
    ///   - progress: called as the work moves through ``DeploymentStage/downloading``,
    ///     ``DeploymentStage/verifying``, ``DeploymentStage/extracting`` and
    ///     ``DeploymentStage/preflight``, with a fraction when one is known.
    /// - Returns: the staged release, ready to activate.
    /// - Throws: ``ServerCoreError``; production is unaffected.
    func stage(
        _ request: DeploymentRequest,
        progress: @Sendable (DeploymentStage, Double?) -> Void
    ) async throws -> StagedRelease

    /// Makes a staged release the one the service runs on its next start, remembering the
    /// previous one for ``rollback(_:)``. Atomic: on return either the new release is current, or
    /// it threw and the old one still is.
    ///
    /// - Parameter release: a release returned by ``stage(_:progress:)``.
    func activate(_ release: StagedRelease) async throws

    /// Makes the previously current release current again. The caller restarts the service and
    /// checks its readiness afterwards, as for a deployment.
    ///
    /// - Parameter service: the service to roll back.
    /// - Returns: the version that is current after the rollback.
    /// - Throws: ``ServerCoreError`` with ``ServerCoreError/Code/notFound`` if there is no previous
    ///   release.
    func rollback(_ service: ServiceID) async throws -> String

    /// Deletes a staged release that will not be activated. Never throws: a leftover staging
    /// directory is cleaned up on the next deployment.
    ///
    /// - Parameter release: a release returned by ``stage(_:progress:)`` and never activated.
    func discard(_ release: StagedRelease) async
}

/// A release that has been downloaded, verified and unpacked beside production, and has passed
/// preflight.
public struct StagedRelease: Sendable, Hashable, Codable {

    /// The deployment that staged it.
    public var deployment: DeploymentID

    /// The service it is for.
    public var service: ServiceID

    /// Its verified manifest.
    public var manifest: ArtifactManifest

    /// The version being installed; the manifest's.
    public var version: String { manifest.version }

    /// Creates a staged release.
    ///
    /// - Parameters:
    ///   - deployment: the deployment that staged it.
    ///   - service: the service it is for.
    ///   - manifest: its verified manifest.
    public init(deployment: DeploymentID, service: ServiceID, manifest: ArtifactManifest) {
        self.deployment = deployment
        self.service = service
        self.manifest = manifest
    }
}
