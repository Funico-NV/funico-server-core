//
//  LogEntry+FNCLog.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import Logging
import ServerCore

extension LogEntry {

    /// Converts a structured log record a Funico server wrote about itself into a host log entry,
    /// so the agent can merge a server's own records into the same stream as journald's.
    ///
    /// swift-log's `trace` becomes `debug`, the nearest syslog priority. Metadata is flattened to
    /// strings, and `source`, `file`, `function` and `line` are kept as fields of the same names.
    ///
    /// Run this on the host that wrote the record: `FNCLog`'s timestamp carries no time zone, so
    /// it is read in this process's. A timestamp that does not parse falls back to now.
    ///
    /// - Parameters:
    ///   - log: the record.
    ///   - service: the service that wrote it.
    ///   - cursor: its position in whatever it was read from, if that has one.
    public init(_ log: FNCLog, service: ServiceID, cursor: String? = nil) {
        var fields: [String: String] = [
            "source": log.source,
            "file": log.file,
            "function": log.function,
            "line": String(log.line),
        ]
        for (key, value) in log.metadata ?? [:] {
            fields[key] = value.description
        }

        self.init(
            cursor: cursor,
            timestamp: log.date ?? Date(),
            priority: LogPriority(log.level),
            message: log.message.description,
            service: service,
            fields: fields
        )
    }
}

extension LogPriority {

    /// The syslog priority nearest a swift-log level. `trace` has no syslog equivalent and becomes
    /// `debug`.
    ///
    /// - Parameter level: a swift-log level.
    public init(_ level: Logger.Level) {
        switch level {
        case .trace, .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning: self = .warning
        case .error: self = .error
        case .critical: self = .critical
        }
    }
}
