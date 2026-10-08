//
//  LogEntry.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One line of a service's log, as the agent reads it from journald or a supervised process.
///
/// Unlike the server-side `FNCLog`, which a Funico server writes about itself, this is what the
/// *host* recorded — so it covers everything the process printed, crashes and systemd's own
/// messages included.
public struct LogEntry: Sendable, Hashable, Codable {

    /// Where this entry sits in the source's log. Pass it as ``LogQuery/afterCursor`` to read what
    /// came next without gaps or repeats — for journald, its `__CURSOR`. Opaque: never parse it.
    /// `nil` when the source has no stable position.
    public var cursor: String?

    /// When the entry was written — not when the agent read it.
    public var timestamp: Date

    /// How severe it is.
    public var priority: LogPriority

    /// The text.
    public var message: String

    /// The service it came from.
    public var service: ServiceID

    /// The process that wrote it. Diagnostic only.
    public var pid: Int32?

    /// Further structured fields worth keeping, such as `SYSLOG_IDENTIFIER`. Never secrets: the
    /// agent forwards a fixed set of journald fields, not the whole record.
    public var fields: [String: String]

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - cursor: the entry's position in its source.
    ///   - timestamp: when it was written.
    ///   - priority: how severe it is.
    ///   - message: the text.
    ///   - service: the service it came from.
    ///   - pid: the process that wrote it.
    ///   - fields: further structured fields.
    public init(
        cursor: String? = nil,
        timestamp: Date,
        priority: LogPriority,
        message: String,
        service: ServiceID,
        pid: Int32? = nil,
        fields: [String: String] = [:]
    ) {
        self.cursor = cursor
        self.timestamp = timestamp
        self.priority = priority
        self.message = message
        self.service = service
        self.pid = pid
        self.fields = fields
    }
}
