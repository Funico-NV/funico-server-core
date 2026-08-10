//
//  AgentControlServer.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

#if Vapor
import Foundation
import Vapor
import ServerFoundationCore
import ServerFoundationLogging

/// The loopback listener a managed server exposes to its agent.
///
/// A **second** Vapor application, sharing the main one's event loop group. It has to be separate:
/// the main listener binds `0.0.0.0` so the app and other services can reach it, and these routes
/// must never be reachable from off-box — `POST /control/shutdown` stops the server.
public final class AgentControlServer: @unchecked Sendable {

    public let configuration: AgentControlConfiguration

    private let application: Application
    private let sequence = SequenceCounter()

    init(configuration: AgentControlConfiguration, application: Application) {
        self.configuration = configuration
        self.application = application
    }

    /// The next event sequence number. Monotonic for the life of the process, which is what makes
    /// `?since=` on the agent's stream able to backfill rather than leave a hole.
    func nextSequence() -> UInt64 {
        sequence.next()
    }

    /// The control channel's pinned JSON coding. Lives in Core so both ends share it.
    public static var encoder: JSONEncoder { AgentControlCoding.encoder }
    public static var decoder: JSONDecoder { AgentControlCoding.decoder }

    /// Stops the listener and tears down the control application.
    ///
    /// The HTTP server has to be stopped explicitly. `asyncShutdown()` alone does not stop a
    /// listener that was started with `server.start(address:)` rather than through the `serve`
    /// command, and Vapor asserts `"HTTPServer did not shutdown before deinitializing"` when the
    /// application is deallocated with one still running.
    public func shutdown() async throws {
        await application.server.shutdown()
        try await application.asyncShutdown()
    }

    final class SequenceCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt64 = 0

        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }
}
#endif
