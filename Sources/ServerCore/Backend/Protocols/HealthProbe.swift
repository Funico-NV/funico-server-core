//
//  HealthProbe.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Asks a running service whether it is ready, beyond what its backend can see.
///
/// systemd reports a unit `active` as soon as its process starts; that is not the same as serving
/// requests. A probe calls the service's own health path — the one its manifest names — and,
/// after a deployment, checks the version it reports, so a restart that silently came back on the
/// old binary is caught.
///
/// Optional: a service without a health path is judged on its backend status alone.
public protocol HealthProbe: Sendable {

    /// Checks one service once. Never throws: an unreachable service is a not-ready result, not an
    /// error. The caller decides how often to retry and when to give up.
    ///
    /// - Parameters:
    ///   - service: a listed service.
    ///   - version: the version it should report, or `nil` to accept any.
    func check(_ service: ServiceID, expecting version: String?) async -> HealthCheckResult
}

/// The answer from one ``HealthProbe`` check.
public struct HealthCheckResult: Sendable, Hashable, Codable {

    /// Whether the service answered healthy, with the expected version if one was given.
    public var isReady: Bool

    /// The version the service reported, if it reported one.
    public var reportedVersion: String?

    /// Why it is not ready, for an operator: a status code, a timeout, a version mismatch.
    public var detail: String?

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - isReady: whether the service is ready.
    ///   - reportedVersion: the version it reported.
    ///   - detail: why it is not ready.
    public init(isReady: Bool, reportedVersion: String? = nil, detail: String? = nil) {
        self.isReady = isReady
        self.reportedVersion = reportedVersion
        self.detail = detail
    }
}
