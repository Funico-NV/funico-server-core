//
//  MockLogSource.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// A `LogSource` over an in-memory log, applying `LogQuery` the way a real source must.
///
/// Entries without a cursor are given one — their position — when appended, so cursor paging
/// works as it does against journald. ``append(_:)`` also delivers to every open
/// ``follow(_:after:)`` stream.
///
/// ```swift
/// let logs = MockLogSource()
/// await logs.append(LogEntry(timestamp: Date(), priority: .error, message: "boom", service: "invoices"))
///
/// let errors = try await logs.entries(of: "invoices", matching: LogQuery(minimumPriority: .error))
/// ```
public actor MockLogSource: LogSource {

    private var log: [ServiceID: [LogEntry]] = [:]
    private var followers: [UUID: (service: ServiceID, continuation: AsyncThrowingStream<LogEntry, any Error>.Continuation)] = [:]
    private var nextPosition = 0

    /// Creates a source holding `entries`, in order.
    ///
    /// - Parameter entries: the starting log.
    public init(entries: [LogEntry] = []) {
        for entry in entries {
            Self.store(entry, in: &log, position: &nextPosition)
        }
    }

    /// Adds an entry to the end of its service's log and delivers it to followers.
    ///
    /// - Parameter entry: the entry; given a cursor if it has none.
    public func append(_ entry: LogEntry) {
        let stored = Self.store(entry, in: &log, position: &nextPosition)
        for follower in followers.values where follower.service == stored.service {
            follower.continuation.yield(stored)
        }
    }

    /// How many ``follow(_:after:)`` streams are open. Lets a test confirm a stream was torn down.
    public var followerCount: Int { followers.count }

    public func entries(of service: ServiceID, matching query: LogQuery) async throws -> [LogEntry] {
        var entries = log[service] ?? []

        if let cursor = query.afterCursor {
            guard let index = entries.firstIndex(where: { $0.cursor == cursor }) else {
                throw ServerCoreError(.notFound, "no entry at cursor \(cursor)")
            }
            entries = Array(entries[(index + 1)...])
        } else if let since = query.since {
            entries = entries.filter { $0.timestamp >= since }
        }
        if let until = query.until {
            entries = entries.filter { $0.timestamp < until }
        }
        if let minimum = query.minimumPriority {
            entries = entries.filter { $0.priority >= minimum }
        }
        if let text = query.contains, !text.isEmpty {
            entries = entries.filter { $0.message.range(of: text, options: .caseInsensitive) != nil }
        }

        // Paging forward from a cursor reads the next page; otherwise the newest entries.
        return query.afterCursor == nil
            ? Array(entries.suffix(query.effectiveLimit))
            : Array(entries.prefix(query.effectiveLimit))
    }

    public func follow(_ service: ServiceID, after cursor: String?) async throws -> AsyncThrowingStream<LogEntry, any Error> {
        let backlog = cursor == nil
            ? []
            : try await entries(of: service, matching: LogQuery(afterCursor: cursor, limit: LogQuery.maximumLimit))

        let (stream, continuation) = AsyncThrowingStream<LogEntry, any Error>.makeStream()
        let id = UUID()
        followers[id] = (service, continuation)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeFollower(id) }
        }
        for entry in backlog {
            continuation.yield(entry)
        }
        return stream
    }

    private func removeFollower(_ id: UUID) {
        followers[id] = nil
    }

    @discardableResult
    private static func store(_ entry: LogEntry, in log: inout [ServiceID: [LogEntry]], position: inout Int) -> LogEntry {
        var entry = entry
        if entry.cursor == nil {
            entry.cursor = "mock-\(position)"
        }
        position += 1
        log[entry.service, default: []].append(entry)
        return entry
    }
}
