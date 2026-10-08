//
//  ServiceDescriptor.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// A service a host has agreed to let the Manager see and operate, as the agent describes it.
///
/// Everything here comes *from* the host's allow-list. The Manager reads it; it never sends one
/// back to define or change a service.
public struct ServiceDescriptor: Sendable, Hashable, Codable, Identifiable {

    /// The service's identifier, used in every command about it.
    public var id: ServiceID

    /// A name for people — `"Invoices"`.
    public var displayName: String

    /// What keeps the service running.
    public var backend: ServiceBackendKind

    /// The systemd unit or process label, shown to an operator for orientation. Informational
    /// only: the agent never accepts a unit name from the Manager, only a ``ServiceID``.
    public var unit: String?

    /// The GitHub repository releases come from, as `owner/name`. `nil` for a service that is not
    /// deployed by the agent.
    public var repository: String?

    /// Whether the agent may deploy releases of this service. A host can list a service so it can
    /// be watched and restarted while its deploys still happen another way — the transition step
    /// that keeps a deployment switch from being silent.
    public var deploysEnabled: Bool

    /// Creates a descriptor.
    ///
    /// - Parameters:
    ///   - id: the service's identifier.
    ///   - displayName: a name for people.
    ///   - backend: what keeps the service running.
    ///   - unit: the systemd unit or process label, for display.
    ///   - repository: the GitHub repository releases come from, as `owner/name`.
    ///   - deploysEnabled: whether the agent may deploy releases of this service.
    public init(
        id: ServiceID,
        displayName: String,
        backend: ServiceBackendKind,
        unit: String? = nil,
        repository: String? = nil,
        deploysEnabled: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.backend = backend
        self.unit = unit
        self.repository = repository
        self.deploysEnabled = deploysEnabled
    }
}
