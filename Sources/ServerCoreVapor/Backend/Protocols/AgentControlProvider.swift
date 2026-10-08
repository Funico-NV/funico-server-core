//
//  AgentControlProvider.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

#if Vapor
import Foundation
import ServerCore

/// What a managed server tells the agent about itself.
///
/// This is the half of the status model the agent cannot observe from the outside. The agent
/// knows whether a process is alive, crashed, wedged or in backoff; only the server knows
/// whether its jobs are idle, running or finished, and how that turned out.
public protocol AgentControlProvider: Sendable {

    /// The server's own view of its state. Called on every health probe, so keep it cheap.
    func serverState() async -> ServerState

    /// What jobs this server has. Answers `GET /control/jobs`, and is what lets the app render
    /// controls for a server it was never compiled against.
    func jobs() async -> [ServerJobDescriptor]

    /// What those jobs are doing right now.
    func jobStates() async -> [ServerJobStatus]
}

public extension AgentControlProvider {

    // Defaulted so that a server with no job concept — `funico-scheduler-api-server`,
    // `funico-kpi-api-server`, the dashboards — adopts the control channel by implementing
    // nothing at all.
    func jobs() async -> [ServerJobDescriptor] { [] }

    func jobStates() async -> [ServerJobStatus] { [] }
}

/// For a server that has no jobs and is either up or not running at all.
///
/// Reporting `.online` unconditionally is honest here: this code only executes inside a
/// process that is serving requests. Whether that process exists is the agent's half of the
/// answer, and the agent already knows it.
public struct StatelessAgentControlProvider: AgentControlProvider {

    public init() {}

    public func serverState() async -> ServerState { .online }
}
#endif
