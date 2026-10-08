//
//  WebSocketBackoff.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// Full-jitter exponential backoff.
///
/// Full jitter — a delay drawn uniformly from `0...cap` rather than the cap itself — is what
/// stops N reconnecting clients from synchronising into a thundering herd after a server
/// restart. With a fixed delay they all retry at the same instant, forever.
public struct WebSocketBackoff: Sendable, Hashable {

    public var initialDelay: Duration
    public var maximumDelay: Duration
    public var multiplier: Double

    public static let `default` = WebSocketBackoff()

    public init(
        initialDelay: Duration = .seconds(1),
        maximumDelay: Duration = .seconds(300),
        multiplier: Double = 2
    ) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.multiplier = max(1, multiplier)
    }

    /// The ceiling for a given attempt, before jitter. `attempt` is zero-based.
    public func ceiling(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return initialDelay }

        let scaled = initialDelay.seconds * pow(multiplier, Double(attempt))
        return .seconds(min(scaled, maximumDelay.seconds))
    }

    /// The delay to wait before `attempt`.
    ///
    /// - Parameters:
    ///   - attempt: zero-based retry count.
    ///   - jitter: injectable so the distribution can be tested deterministically. Returns a value
    ///     in `0...1` that scales the ceiling; anything outside that range is clamped.
    public func delay(
        forAttempt attempt: Int,
        jitter: @Sendable () -> Double = { Double.random(in: 0...1) }
    ) -> Duration {
        let bounded = min(max(jitter(), 0), 1)
        return .seconds(ceiling(forAttempt: attempt).seconds * bounded)
    }
}

extension Duration {

    /// This duration in seconds.
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
