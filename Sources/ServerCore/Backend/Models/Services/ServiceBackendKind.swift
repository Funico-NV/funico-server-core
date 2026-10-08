//
//  ServiceBackendKind.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Which mechanism keeps a service running on its host.
///
/// Open, so a new backend — a container runtime, launchd — does not need every client rebuilt
/// before an agent may report it.
public struct ServiceBackendKind: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// A systemd unit. The production backend on Linux: systemd owns restarts, so the agent
    /// starting, stopping or crashing never takes a service down with it.
    public static let systemd = ServiceBackendKind("systemd")

    /// A child process of the agent itself. For macOS and development, where there is no systemd;
    /// the service stops if the agent does.
    public static let supervisedProcess = ServiceBackendKind("supervisedProcess")
}
