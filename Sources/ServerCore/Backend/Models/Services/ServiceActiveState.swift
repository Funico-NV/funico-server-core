//
//  ServiceActiveState.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The coarse state of a service, using systemd's `ActiveState` vocabulary.
///
/// systemd's names are used for every backend, so the app has one set of states to render. The
/// supervised-process backend maps onto them: a running child is ``active``, a crashed one
/// ``failed``.
///
/// systemd has added states before (`maintenance` in v244, `refreshing` in v254). Decoding an
/// unrecognised value yields ``unknown`` rather than failing, so a newer host never makes an older
/// app unable to read the rest of a status.
public enum ServiceActiveState: String, Sendable, Hashable, Codable, CaseIterable {

    /// Running.
    case active

    /// Running, and reloading its configuration.
    case reloading

    /// Stopped, cleanly or because it was never started.
    case inactive

    /// Stopped after a crash, a non-zero exit, a timeout or too many restarts.
    case failed

    /// Starting.
    case activating

    /// Stopping.
    case deactivating

    /// systemd is cleaning up after the service (its runtime or state directories).
    case maintenance

    /// systemd is refreshing the service's mounts or bind mounts.
    case refreshing

    /// The backend reported something this version does not know, or could not be asked.
    case unknown

    /// Decodes a state, mapping anything unrecognised to ``unknown``.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ServiceActiveState(rawValue: value) ?? .unknown
    }

    /// Whether the service is up or on its way up — what a dashboard shows as green or amber.
    public var isRunning: Bool {
        switch self {
        case .active, .reloading, .activating, .refreshing: true
        case .inactive, .failed, .deactivating, .maintenance, .unknown: false
        }
    }
}
