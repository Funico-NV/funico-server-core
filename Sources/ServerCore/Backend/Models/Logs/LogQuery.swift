//
//  LogQuery.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Which log entries of one service to read.
///
/// Every field narrows the result; an empty query asks for the most recent ``defaultLimit``
/// entries.
public struct LogQuery: Sendable, Hashable, Codable {

    /// How many entries a query returns when ``limit`` is not set.
    public static let defaultLimit = 200

    /// The most a single query may return, however large ``limit`` is. A log can be gigabytes; a
    /// page has to fit in one WebSocket frame and in a phone's memory. Page with
    /// ``afterCursor`` for more.
    public static let maximumLimit = 5_000

    /// Only entries at or after this time.
    public var since: Date?

    /// Only entries before this time.
    public var until: Date?

    /// Only entries after this position — a ``LogEntry/cursor`` from an earlier page. Takes
    /// precedence over ``since``.
    public var afterCursor: String?

    /// Only entries this severe or worse.
    public var minimumPriority: LogPriority?

    /// Only entries whose message contains this text, compared literally and case-insensitively.
    ///
    /// A plain substring rather than a regular expression, on purpose: a pattern from a client
    /// would otherwise reach journald's PCRE engine on the host, where a pathological one can pin
    /// a CPU.
    public var contains: String?

    /// How many entries to return at most, newest last. Clamped to `1...maximumLimit`; see
    /// ``effectiveLimit``.
    public var limit: Int?

    /// The number of entries a source should actually return: ``limit`` clamped to
    /// `1...maximumLimit`, or ``defaultLimit`` when unset.
    public var effectiveLimit: Int {
        min(max(limit ?? Self.defaultLimit, 1), Self.maximumLimit)
    }

    /// Creates a query.
    ///
    /// - Parameters:
    ///   - since: only entries at or after this time.
    ///   - until: only entries before this time.
    ///   - afterCursor: only entries after this position.
    ///   - minimumPriority: only entries this severe or worse.
    ///   - contains: only entries whose message contains this text.
    ///   - limit: how many entries to return at most.
    public init(
        since: Date? = nil,
        until: Date? = nil,
        afterCursor: String? = nil,
        minimumPriority: LogPriority? = nil,
        contains: String? = nil,
        limit: Int? = nil
    ) {
        self.since = since
        self.until = until
        self.afterCursor = afterCursor
        self.minimumPriority = minimumPriority
        self.contains = contains
        self.limit = limit
    }
}
