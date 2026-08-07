//
//  ServerEventEnvelope.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation
import ServerFoundationCore

/// A topic on the multiplexed event stream, used to filter
/// `WS /v1/events?servers=…&topics=…`.
public struct ServerEventTopic: Sendable, Hashable, RawRepresentable, Identifiable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var id: String { rawValue }
}

extension ServerEventTopic {

    public static let state = ServerEventTopic("state")
    public static let jobs = ServerEventTopic("jobs")
    public static let log = ServerEventTopic("log")
}

extension ServerEventTopic: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One event on the agent's multiplexed stream.
///
/// This is the versioned JSON envelope that all *new* traffic uses. The legacy
/// `"id;iso8601"` strings stay frozen on the three existing endpoints — they have no room
/// for a version, a type tag, or a job result — and a thin adapter formats this model down
/// into them for the shipped iOS build.
///
/// It lives in `ServerFoundationLogging` rather than `Core` because it is the one type that
/// needs both the domain vocabulary *and* ``FNCLog``, and `Core` must not gain a swift-log
/// dependency. Anything consuming this stream consumes logs anyway.
public struct ServerEventEnvelope: Sendable, Codable, Identifiable {

    /// Bumped only for a breaking change to the envelope itself. New ``Payload`` cases are
    /// additive and do not bump it.
    public static let currentVersion = 1

    public let version: Int

    /// Monotonically increasing per agent. This is what makes a reconnect resumable:
    /// `?since=<sequence>` backfills what was missed instead of leaving a silent hole,
    /// which is exactly the failure mode of the current WebSocket modifiers.
    public let sequence: UInt64

    /// Slug of the server this is about — `"invoices"`, `"scheduler"`.
    public let serverID: String

    public let emittedAt: Date

    public let payload: Payload

    public var id: UInt64 { sequence }

    public var topic: ServerEventTopic {
        switch payload {
        case .state: .state
        case .jobState, .jobs: .jobs
        case .log: .log
        }
    }

    public init(
        version: Int = ServerEventEnvelope.currentVersion,
        sequence: UInt64,
        serverID: String,
        emittedAt: Date = Date(),
        payload: Payload
    ) {
        self.version = version
        self.sequence = sequence
        self.serverID = serverID
        self.emittedAt = emittedAt
        self.payload = payload
    }

    /// What the event actually carries.
    ///
    /// - Note: deployment events are not here yet. The deploy state machine does not exist,
    ///   and inventing its payload before it does would be guessing. Adding a case later is
    ///   additive — that is what ``version`` is protecting.
    public enum Payload: Sendable, Codable {

        case state(ServerState)

        /// A single job changed. Lossless, unlike the legacy codec — a job that completed
        /// and a job that failed are distinguishable here.
        case jobState(job: ServerJob, state: ServerJobState)

        /// The server's job list, as answered by `GET /v1/servers/{id}/jobs`.
        case jobs([ServerJobDescriptor])

        case log(FNCLog)
    }
}
