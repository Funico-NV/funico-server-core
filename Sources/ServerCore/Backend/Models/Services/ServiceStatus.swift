//
//  ServiceStatus.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// What a service is doing right now, as its backend reports it.
///
/// Every field but ``service`` and ``activeState`` is optional because not every backend can
/// answer it, and an absent value must not be confused with zero: a ``restartCount`` of `nil`
/// means "not reported", while `0` means "has not restarted".
public struct ServiceStatus: Sendable, Hashable, Codable {

    /// The service this is about.
    public var service: ServiceID

    /// The coarse state. Drive the UI from this.
    public var activeState: ServiceActiveState

    /// The backend's finer state — for systemd, `SubState` such as `"running"`, `"exited"`,
    /// `"auto-restart"`. Shown to an operator, never switched on: its vocabulary differs per unit
    /// type and per backend.
    public var subState: String?

    /// When the service entered ``activeState``.
    public var since: Date?

    /// The main process ID while running. Diagnostic only: pids are recycled, so never use one to
    /// identify or signal a process.
    public var mainPID: Int32?

    /// How many times the backend has restarted the service automatically since it was last
    /// started by hand. systemd's `NRestarts`.
    public var restartCount: Int?

    /// The exit status of the last main process that exited, if any. Non-zero after a crash.
    public var lastExitStatus: Int32?

    /// The version the host reports as installed, from the release's manifest.
    public var version: String?

    /// Creates a status.
    ///
    /// - Parameters:
    ///   - service: the service this is about.
    ///   - activeState: the coarse state.
    ///   - subState: the backend's finer state, for display.
    ///   - since: when the service entered `activeState`.
    ///   - mainPID: the main process ID, for diagnostics.
    ///   - restartCount: automatic restarts since the last manual start.
    ///   - lastExitStatus: the exit status of the last main process to exit.
    ///   - version: the installed release's version.
    public init(
        service: ServiceID,
        activeState: ServiceActiveState,
        subState: String? = nil,
        since: Date? = nil,
        mainPID: Int32? = nil,
        restartCount: Int? = nil,
        lastExitStatus: Int32? = nil,
        version: String? = nil
    ) {
        self.service = service
        self.activeState = activeState
        self.subState = subState
        self.since = since
        self.mainPID = mainPID
        self.restartCount = restartCount
        self.lastExitStatus = lastExitStatus
        self.version = version
    }
}
