//
//  MockServiceBackend.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// A `ServiceBackend` that keeps services in memory and records what it was asked to do.
///
/// Behaves like a well-run host: `start` and `restart` leave a service `active`, `stop` leaves it
/// `inactive`, and an unlisted service is refused with `unknownService`, exactly as a real backend
/// must. ``fail(_:with:)`` makes one service's operations throw, to exercise error paths.
///
/// ```swift
/// let backend = MockServiceBackend(services: [
///     ServiceDescriptor(id: "invoices", displayName: "Invoices", backend: .systemd)
/// ])
/// try await backend.perform(.restart, on: "invoices")
///
/// let operations = await backend.performed   // [PerformedOperation(.restart, "invoices")]
/// ```
public actor MockServiceBackend: ServiceBackend {

    /// One call to ``perform(_:on:)``, as recorded.
    public struct PerformedOperation: Sendable, Hashable {

        /// What was asked.
        public var operation: ServiceOperation

        /// Of which service.
        public var service: ServiceID

        /// Creates a record.
        ///
        /// - Parameters:
        ///   - operation: what was asked.
        ///   - service: of which service.
        public init(_ operation: ServiceOperation, _ service: ServiceID) {
            self.operation = operation
            self.service = service
        }
    }

    private var descriptors: [ServiceDescriptor]
    private var statuses: [ServiceID: ServiceStatus]
    private var failures: [ServiceID: ServerCoreError] = [:]

    /// Every operation performed, in order, including ones that threw.
    public private(set) var performed: [PerformedOperation] = []

    /// Creates a backend listing `services`, each `inactive` unless `statuses` says otherwise.
    ///
    /// - Parameters:
    ///   - services: the services the host lists.
    ///   - statuses: starting statuses; services without one start `inactive`.
    public init(services: [ServiceDescriptor], statuses: [ServiceStatus] = []) {
        self.descriptors = services
        var initial: [ServiceID: ServiceStatus] = [:]
        for service in services {
            initial[service.id] = ServiceStatus(service: service.id, activeState: .inactive)
        }
        for status in statuses {
            initial[status.service] = status
        }
        self.statuses = initial
    }

    /// Makes every later call about `service` throw `error`, until ``recover(_:)``.
    ///
    /// - Parameters:
    ///   - service: the service whose calls should fail.
    ///   - error: what they throw.
    public func fail(_ service: ServiceID, with error: ServerCoreError) {
        failures[service] = error
    }

    /// Undoes ``fail(_:with:)``.
    ///
    /// - Parameter service: the service whose calls should succeed again.
    public func recover(_ service: ServiceID) {
        failures[service] = nil
    }

    /// Replaces a service's status, as if something on the host changed it — a crash, say.
    ///
    /// - Parameter status: the new status.
    public func setStatus(_ status: ServiceStatus) {
        statuses[status.service] = status
    }

    public func services() async throws -> [ServiceDescriptor] {
        descriptors
    }

    public func status(of service: ServiceID) async throws -> ServiceStatus {
        try check(service)
        return statuses[service]!
    }

    public func perform(_ operation: ServiceOperation, on service: ServiceID) async throws {
        performed.append(PerformedOperation(operation, service))
        try check(service)

        var status = statuses[service]!
        let previousState = status.activeState
        switch operation {
        case .start, .restart:
            status.activeState = .active
            status.subState = "running"
        case .stop:
            status.activeState = .inactive
            status.subState = "dead"
        }
        if status.activeState != previousState || operation == .restart {
            status.since = Date()
        }
        statuses[service] = status
    }

    private func check(_ service: ServiceID) throws {
        guard statuses[service] != nil else {
            throw ServerCoreError(.unknownService, "\(service) is not listed on this host")
        }
        if let failure = failures[service] {
            throw failure
        }
    }
}
