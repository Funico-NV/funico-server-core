//
//  ServerJobState.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// What a job is doing right now.
///
/// Generalised from `InvoiceJob.State`, with one change: the terminal case carries a
/// ``ServerJobResult`` instead of collapsing every ending into "canceled".
public enum ServerJobState: Sendable, Hashable, Codable {

    case executing(since: Date)
    case running(since: Date)
    case paused(on: Date)
    case idle(since: Date)

    /// The run ended. `result` is what the legacy codec cannot express.
    case finished(ServerJobResult, on: Date)
}

extension ServerJobState: Identifiable {

    /// - Note: `"canceled"` reconstructs `.finished(.cancelled, …)`, because that is the
    ///   only terminal state the legacy vocabulary has. A run that actually completed or
    ///   failed is only distinguishable when it arrives via `ServerEventEnvelope`.
    public init?(id: String, date: Date) {
        switch id {
        case "executing": self = .executing(since: date)
        case "running": self = .running(since: date)
        case "paused": self = .paused(on: date)
        case "idle": self = .idle(since: date)
        case "canceled": self = .finished(.cancelled, on: date)
        default: return nil
        }
    }

    /// - Important: the terminal case is `"canceled"` — American spelling, one `l` — because
    ///   that is the exact byte sequence `funico-invoices-service` emits today and a shipped
    ///   iOS build has persisted. The Swift case is `.cancelled`. Do not "fix" either one to
    ///   match the other.
    public var id: String {
        switch self {
        case .executing: "executing"
        case .running: "running"
        case .paused: "paused"
        case .idle: "idle"
        case .finished: "canceled"
        }
    }

    public var date: Date {
        switch self {
        case .executing(let date): date
        case .running(let date): date
        case .paused(let date): date
        case .idle(let date): date
        case .finished(_, let date): date
        }
    }

    public var title: String {
        switch self {
        case .executing: "Executing"
        case .running: "Running"
        case .paused: "Paused"
        case .idle: "Idle"
        case .finished(let result, _): result.title
        }
    }

    /// The result of a finished run, if this is one.
    public var result: ServerJobResult? {
        switch self {
        case .finished(let result, _): result
        case .executing, .running, .paused, .idle: nil
        }
    }

    /// Why a finished run failed, if it did.
    public var failureReason: String? {
        result?.failureReason
    }

    /// True while the job is doing work — the states a stop or pause control applies to.
    public var isActive: Bool {
        switch self {
        case .executing, .running: true
        case .paused, .idle, .finished: false
        }
    }
}

extension ServerJobState: RawRepresentable {

    /// The legacy `"id;iso8601"` codec.
    ///
    /// Lossy by construction: `.finished(.completed, …)`, `.finished(.cancelled, …)` and
    /// `.finished(.failed(…), …)` all render as `"canceled;<date>"` and all read back as
    /// `.cancelled`. That is not a bug to fix here — extending this string is what
    /// silently drops a user's persisted `@AppStorage` job selection. `ServerEventEnvelope`
    /// is the lossless path.
    public init?(rawValue: String) {
        let components = rawValue.split(separator: ";")
        guard components.count == 2 else { return nil }

        guard let date = Date.fromISO8601String(String(components[1])) else { return nil }
        self.init(id: String(components[0]), date: date)
    }

    public var rawValue: String {
        [id, date.iso8601String].joined(separator: ";")
    }
}

extension ServerJobState {

    /// Encoded losslessly, as a keyed object — **not** via ``rawValue``.
    ///
    /// This has to be written out by hand. The standard library ships
    /// `extension RawRepresentable where RawValue: Codable, Self: Codable`, and those
    /// default implementations take precedence over the compiler's synthesis for enums with
    /// associated values. Conforming to both protocols and saying nothing therefore routes
    /// JSON straight through the lossy legacy string: `.finished(.failed("db down"))` goes
    /// out as `"canceled;…"` and comes back as `.cancelled`, losing the reason — silently,
    /// on the path that exists *specifically* to preserve it.
    private enum CodingKeys: String, CodingKey {
        case state
        case date
        case result
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(String.self, forKey: .state)
        let date = try container.decode(Date.self, forKey: .date)

        switch state {
        case "executing": self = .executing(since: date)
        case "running": self = .running(since: date)
        case "paused": self = .paused(on: date)
        case "idle": self = .idle(since: date)
        case "finished":
            self = .finished(try container.decode(ServerJobResult.self, forKey: .result), on: date)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Unrecognised job state '\(state)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)

        switch self {
        case .executing: try container.encode("executing", forKey: .state)
        case .running: try container.encode("running", forKey: .state)
        case .paused: try container.encode("paused", forKey: .state)
        case .idle: try container.encode("idle", forKey: .state)
        case .finished(let result, _):
            // "finished", not the legacy "canceled" — this codec is allowed to be correct.
            try container.encode("finished", forKey: .state)
            try container.encode(result, forKey: .result)
        }
    }
}
