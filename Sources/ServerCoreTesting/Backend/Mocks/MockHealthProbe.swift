//
//  MockHealthProbe.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// A `HealthProbe` that answers ready, reporting whatever version was expected, unless told
/// otherwise with ``setResult(_:for:)``.
public actor MockHealthProbe: HealthProbe {

    private var results: [ServiceID: HealthCheckResult] = [:]

    /// How many checks each service has had. Lets a test confirm a readiness loop polled.
    public private(set) var checkCounts: [ServiceID: Int] = [:]

    /// Creates a probe that answers ready for everything.
    public init() {}

    /// Fixes the answer for one service; `nil` restores the default.
    ///
    /// - Parameters:
    ///   - result: the answer to give.
    ///   - service: the service it applies to.
    public func setResult(_ result: HealthCheckResult?, for service: ServiceID) {
        results[service] = result
    }

    public func check(_ service: ServiceID, expecting version: String?) async -> HealthCheckResult {
        checkCounts[service, default: 0] += 1
        return results[service] ?? HealthCheckResult(isReady: true, reportedVersion: version)
    }
}
