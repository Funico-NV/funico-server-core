//
//  MockDeploymentExecutor.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// A `DeploymentExecutor` that tracks current and previous versions in memory and can be told to
/// fail at any stage.
///
/// Staging reports every pre-activation stage through `progress` and produces a valid manifest for
/// the requested service and version. It refuses a `DeploymentRequest` for a service it was not
/// given, as a real executor refuses one the allow-list does not name.
///
/// ```swift
/// let executor = MockDeploymentExecutor(currentVersions: ["invoices": "1.5.2"])
/// await executor.failAt(.verifying)
/// ```
public actor MockDeploymentExecutor: DeploymentExecutor {

    private var current: [ServiceID: String]
    private var previous: [ServiceID: String] = [:]
    private var failingStage: DeploymentStage?

    /// Every request passed to ``stage(_:progress:)``, in order.
    public private(set) var stagedRequests: [DeploymentRequest] = []

    /// Every release that was activated, in order.
    public private(set) var activated: [StagedRelease] = []

    /// Every release that was discarded, in order.
    public private(set) var discarded: [StagedRelease] = []

    /// Creates an executor for the services in `currentVersions`, each running that version.
    ///
    /// - Parameter currentVersions: the version each known service is running.
    public init(currentVersions: [ServiceID: String]) {
        self.current = currentVersions
    }

    /// Makes the next deployments fail on reaching `stage`: one of the staging stages makes
    /// ``stage(_:progress:)`` throw, `DeploymentStage/activating` makes ``activate(_:)`` throw.
    /// `nil` stops failing.
    ///
    /// - Parameter stage: the stage to fail at.
    public func failAt(_ stage: DeploymentStage?) {
        failingStage = stage
    }

    /// The version a service is running, as far as this executor knows.
    ///
    /// - Parameter service: the service.
    public func currentVersion(of service: ServiceID) -> String? {
        current[service]
    }

    public func stage(
        _ request: DeploymentRequest,
        progress: @Sendable (DeploymentStage, Double?) -> Void
    ) async throws -> StagedRelease {
        stagedRequests.append(request)
        guard current[request.service] != nil else {
            throw ServerCoreError(.unknownService, "\(request.service) is not listed on this host")
        }

        for stage in [DeploymentStage.downloading, .verifying, .extracting, .preflight] {
            progress(stage, nil)
            if stage == failingStage {
                throw ServerCoreError(stage == .verifying ? .verificationFailed : .backendFailure, "failing at \(stage) as configured")
            }
        }

        let entrypoint = "bin/\(request.service)"
        let manifest = ArtifactManifest(
            service: request.service,
            version: request.version,
            gitCommit: String(repeating: "0", count: 40),
            platform: request.artifact.platform,
            entrypoint: entrypoint,
            files: [entrypoint: String(repeating: "0", count: 64)]
        )
        return StagedRelease(deployment: request.deployment, service: request.service, manifest: manifest)
    }

    public func activate(_ release: StagedRelease) async throws {
        if failingStage == .activating {
            throw ServerCoreError(.backendFailure, "failing at activating as configured")
        }
        previous[release.service] = current[release.service]
        current[release.service] = release.version
        activated.append(release)
    }

    public func rollback(_ service: ServiceID) async throws -> String {
        guard let version = previous[service] else {
            throw ServerCoreError(.notFound, "\(service) has no previous release")
        }
        previous[service] = current[service]
        current[service] = version
        return version
    }

    public func discard(_ release: StagedRelease) async {
        discarded.append(release)
    }
}
