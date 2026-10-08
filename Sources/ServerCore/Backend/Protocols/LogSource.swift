//
//  LogSource.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Where a host's service logs are read from — journald on Linux, captured output on macOS.
///
/// Cursor-based on purpose. Every ``LogEntry`` carries its position, and passing the last one seen
/// as ``LogQuery/afterCursor`` continues exactly where a page, or a dropped connection, left off:
/// no gap, no repeat. Time-based paging cannot promise that when two entries share a timestamp.
///
/// Like ``ServiceBackend``, an implementation answers only for listed services.
public protocol LogSource: Sendable {

    /// A page of a service's log, oldest first, at most ``LogQuery/effectiveLimit`` entries long.
    ///
    /// - Parameters:
    ///   - service: a listed service.
    ///   - query: which entries.
    func entries(of service: ServiceID, matching query: LogQuery) async throws -> [LogEntry]

    /// New entries as they are written, until the stream is cancelled.
    ///
    /// - Parameters:
    ///   - service: a listed service.
    ///   - cursor: start after this entry; `nil` starts from now.
    func follow(_ service: ServiceID, after cursor: String?) async throws -> AsyncThrowingStream<LogEntry, any Error>
}
