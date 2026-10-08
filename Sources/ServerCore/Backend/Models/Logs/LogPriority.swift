//
//  LogPriority.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// How severe a log entry is, on the syslog scale journald uses.
///
/// Encoded by name (`"error"`), not by syslog number, so a log stream reads without a lookup
/// table. ``syslogLevel`` and ``init(syslogLevel:)`` convert to and from journald's `PRIORITY`.
///
/// Ordered by severity: `.error > .warning`, so "this bad or worse" is `entry.priority >= .warning`.
public enum LogPriority: String, Sendable, Hashable, Codable, CaseIterable, Comparable {

    case debug
    case info
    case notice
    case warning
    case error
    case critical
    case alert
    case emergency

    /// journald's `PRIORITY` field: `0` (emergency) to `7` (debug).
    public var syslogLevel: Int {
        switch self {
        case .emergency: 0
        case .alert: 1
        case .critical: 2
        case .error: 3
        case .warning: 4
        case .notice: 5
        case .info: 6
        case .debug: 7
        }
    }

    /// Converts journald's `PRIORITY`. Returns `nil` outside `0...7`.
    ///
    /// - Parameter syslogLevel: `0` (emergency) to `7` (debug).
    public init?(syslogLevel: Int) {
        guard let priority = Self.allCases.first(where: { $0.syslogLevel == syslogLevel }) else {
            return nil
        }
        self = priority
    }

    public static func < (lhs: LogPriority, rhs: LogPriority) -> Bool {
        lhs.syslogLevel > rhs.syslogLevel
    }
}
