//
//  ControlPayloads.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

// The control channel's wire types live in Core, not in the Vapor layer, because both ends need
// them: the managed server serves them, and the agent — which must never link Vapor — parses them.
// Only the routing and the `Content` conformances belong on the server side.

/// One job and what it is currently doing.
///
/// An array rather than a `[ServerJob: ServerJobState]` dictionary on purpose: `ServerJob` is a
/// struct, and `JSONEncoder` renders a dictionary with non-`String` keys as a flat array of
/// alternating keys and values — unreadable in a spec and hostile to any non-Swift client.
public struct ServerJobStatus: Sendable, Codable, Hashable, Identifiable {

    public let job: ServerJob
    public let state: ServerJobState

    public var id: String { job.rawValue }

    public init(job: ServerJob, state: ServerJobState) {
        self.job = job
        self.state = state
    }
}

/// `GET /control/health`
public struct ControlHealth: Sendable, Codable, Hashable {

    /// Echoed back so the agent can prove this is the process it launched, and not something else
    /// that has since taken the port.
    public let instanceID: String

    public let uptime: TimeInterval
    public let version: String
    public let state: ServerState

    public init(instanceID: String, uptime: TimeInterval, version: String, state: ServerState) {
        self.instanceID = instanceID
        self.uptime = uptime
        self.version = version
        self.state = state
    }
}

/// `GET /control/state`
public struct ControlState: Sendable, Codable, Hashable {

    public let instanceID: String
    public let state: ServerState
    public let jobs: [ServerJobStatus]

    public init(instanceID: String, state: ServerState, jobs: [ServerJobStatus]) {
        self.instanceID = instanceID
        self.state = state
        self.jobs = jobs
    }
}

/// The control channel's own JSON coding, pinned rather than inherited.
///
/// Vapor's `ContentConfiguration.global` is process-wide and writable, so a managed server that
/// installs its own encoder — a different date strategy, snake_case keys — would silently change
/// what the agent receives. The agent is not that server's API client and must not be at the mercy
/// of its content configuration, so both ends encode and decode explicitly through these.
///
/// ISO-8601 dates: readable in a spec, unambiguous across languages, stable.
public enum AgentControlCoding {

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
