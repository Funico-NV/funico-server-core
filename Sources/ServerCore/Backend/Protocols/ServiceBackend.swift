//
//  ServiceBackend.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The mechanism that keeps services running on a host, reduced to what the Manager may ask of it.
///
/// The agent implements one per backend — systemd on Linux, a process supervisor on macOS — and
/// `ServerCoreTesting` provides a mock. Nothing outside these three requirements is reachable
/// through a backend: no arbitrary unit, no `daemon-reload`, no enabling or masking. Those are
/// host administration, done by a person.
///
/// An implementation must answer only for services in the host's allow-list, and throw
/// ``ServerCoreError/Code/unknownService`` for anything else — including a service that exists on
/// the host but is not listed.
public protocol ServiceBackend: Sendable {

    /// Every service the host lists.
    func services() async throws -> [ServiceDescriptor]

    /// The current status of one service.
    ///
    /// - Parameter service: a listed service.
    /// - Throws: ``ServerCoreError`` with ``ServerCoreError/Code/unknownService`` if it is not
    ///   listed.
    func status(of service: ServiceID) async throws -> ServiceStatus

    /// Starts, stops or restarts a service and returns once the backend has accepted the request.
    ///
    /// Returning does not mean the service is up: a restart that systemd has queued has not
    /// necessarily finished. Read ``status(of:)`` afterwards, or wait on a ``HealthProbe``.
    ///
    /// - Parameters:
    ///   - operation: what to do.
    ///   - service: a listed service.
    /// - Throws: ``ServerCoreError`` with ``ServerCoreError/Code/unknownService`` or
    ///   ``ServerCoreError/Code/backendFailure``.
    func perform(_ operation: ServiceOperation, on service: ServiceID) async throws
}
