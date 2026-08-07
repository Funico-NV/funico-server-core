//
//  ServerState.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 20/01/2026.
//

import Foundation

/// What a server reports about itself.
///
/// Promoted verbatim from `funico-invoices-api`, where it was already generic but stranded
/// in an invoices-shaped package. The cases, the `id` strings and the `rawValue` format are
/// unchanged on purpose — see ``rawValue``.
///
/// - Note: `.offline`, `.maintenance` and `.unknown` are currently unreachable from
///   `funico-invoices-service`, which derives state from `scheduler.isIdle()` and can only
///   ever emit `.online` or `.inactive`. The vocabulary is correct; the reporting side is
///   what needs fixing, in the control channel.
public enum ServerState: Sendable, Hashable, Codable {

    /// The server is online and operational.
    case online
    /// The server is offline and not reachable.
    case offline
    /// The server is online but no tasks are running.
    case inactive
    /// The server is undergoing maintenance.
    case maintenance(since: Date)

    case unknown
}

extension ServerState: Identifiable {

    public init?(id: String, date: Date?) {
        switch id {
        case "online": self = .online
        case "offline": self = .offline
        case "inactive": self = .inactive
        case "maintenance":
            guard let date else { return nil }
            self = .maintenance(since: date)
        case "unknown": self = .unknown
        default: return nil
        }
    }

    public var id: String {
        switch self {
        case .online: "online"
        case .offline: "offline"
        case .inactive: "inactive"
        case .maintenance: "maintenance"
        case .unknown: "unknown"
        }
    }

    public var date: Date? {
        switch self {
        case .maintenance(let date): date
        case .online, .offline, .inactive, .unknown: nil
        }
    }
}

extension ServerState: RawRepresentable {

    /// The legacy `"id"` / `"id;iso8601"` wire codec.
    ///
    /// Kept, and deliberately not extended. It carries no version field and no type tag,
    /// and `split(separator: ";")` on a payload that could contain a `;` is a latent parse
    /// failure — so all *new* traffic uses `ServerEventEnvelope` instead, and this stays
    /// frozen for the three legacy endpoints and for `@AppStorage`.
    public init?(rawValue: String) {
        let components = rawValue.split(separator: ";")

        if components.count == 1 {
            self.init(id: String(components[0]), date: nil)
        } else if components.count == 2 {
            let date = Date.fromISO8601String(String(components[1]))
            self.init(id: String(components[0]), date: date)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        guard let date else { return id }
        return [id, date.iso8601String].joined(separator: ";")
    }
}

extension ServerState {

    /// Encoded as its ``rawValue`` string, spelled out rather than inherited.
    ///
    /// Unlike ``ServerJobState``, the legacy codec *is* lossless for this type, so routing
    /// JSON through it is correct. It is written explicitly anyway so the behaviour is a
    /// decision in the file rather than a consequence of which of two conformances the
    /// standard library happens to prefer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let state = ServerState(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised server state '\(rawValue)'"
            )
        }
        self = state
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
