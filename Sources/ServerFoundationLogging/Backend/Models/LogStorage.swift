//
//  LogStorage.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 02/10/2025.
//

import Foundation
import Logging

/// A bounded in-memory log ring with live observers.
///
/// Two deliberate departures from the `InvoicesLogging` original:
///
/// 1. **It is a lock-protected class, not an actor.** `LogHandler.log(event:)` is
///    synchronous, so an actor forces every call site into `Task { await … }` — and
///    unstructured tasks have no ordering guarantee, so log lines can be *stored out of
///    order*. That is a real defect in the current implementation. A lock makes `append`
///    synchronous and ordering trivially correct.
/// 2. **No `swift-async-observer` dependency.** Observation is an `AsyncStream`, which is
///    what the agent and the app both want anyway, and it keeps this package free of an
///    `NVMNovem` dependency that seven servers would otherwise inherit.
public final class LogStorage: @unchecked Sendable {

    /// Matches the original ring size.
    public static let defaultCapacity = 10_000

    private let lock = NSLock()
    private let capacity: Int

    private var buffer: [FNCLog?]
    private var head = 0
    private var storedCount = 0

    private var subscribers: [UUID: AsyncStream<FNCLog>.Continuation] = [:]

    public init(capacity: Int = LogStorage.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.buffer = Array(repeating: nil, count: max(1, capacity))
    }

    /// Stores a log and hands it to every live observer.
    ///
    /// A true ring — the original called `Array.removeFirst()` on every append past the
    /// limit, which moves 10,000 elements each time a chatty server logs a line.
    public func append(_ log: FNCLog) {
        lock.lock()
        defer { lock.unlock() }

        buffer[(head + storedCount) % capacity] = log

        if storedCount < capacity {
            storedCount += 1
        } else {
            head = (head + 1) % capacity
        }

        // Yielding under the lock is what keeps observers in the same order as storage.
        // `yield` only enqueues — it does not run consumer code and cannot re-enter here.
        for continuation in subscribers.values {
            continuation.yield(log)
        }
    }

    /// Everything currently held, oldest first.
    public func all() -> [FNCLog] {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    /// A live stream of logs.
    ///
    /// - Parameter replayingExisting: when true, everything already stored is delivered
    ///   first. Registration and replay happen under the same lock, so a log arriving
    ///   mid-subscription is neither missed nor delivered twice.
    public func stream(replayingExisting: Bool = false) -> AsyncStream<FNCLog> {
        let id = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(capacity)) { continuation in
            lock.lock()

            if replayingExisting {
                for log in snapshotLocked() {
                    continuation.yield(log)
                }
            }
            subscribers[id] = continuation

            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.subscribers[id] = nil
                self.lock.unlock()
            }
        }
    }

    private func snapshotLocked() -> [FNCLog] {
        (0..<storedCount).compactMap { buffer[(head + $0) % capacity] }
    }
}
