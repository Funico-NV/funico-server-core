//
//  ResilientWebSocket.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A WebSocket that reconnects.
///
/// Replaces the pattern in `funico-invoices-api` 1.2.5, where all three view modifiers
/// `break` out of the receive loop on the *first* error with no retry. Recovery there only
/// happens if the user backgrounds and foregrounds the app, so a server restart leaves a
/// silently dead view until someone notices.
///
/// What this does instead:
///
/// - reconnects with full-jitter exponential backoff, indefinitely, until cancelled
/// - derives `ws`/`wss` from the base URL rather than hardcoding `ws://`
/// - sends credentials as an `Authorization` header on the `URLRequest`, never in the query
///   string, where they would land in server logs and proxy caches
/// - rebuilds the URL per attempt, so a reconnect can carry `?since=<sequence>` and backfill
///   what it missed rather than leaving a hole
public actor ResilientWebSocket {

    private let connectionURL: @Sendable () async -> URL?
    private let headers: [String: String]
    private let transport: any WebSocketTransport
    private let backoff: WebSocketBackoff
    private let logger: Logger

    private var pump: Task<Void, Never>?

    /// - Parameters:
    ///   - connectionURL: evaluated before every attempt. Return a URL carrying `?since=` to
    ///     resume a stream; return `nil` to stop reconnecting.
    ///   - headers: sent on the upgrade request. Put the bearer token here.
    ///   - transport: how connections are opened. Substitutable so reconnection can be tested
    ///     without starting and killing a real server.
    ///   - backoff: how long to wait between attempts.
    ///   - logger: where drops and retries are reported.
    public init(
        connectionURL: @escaping @Sendable () async -> URL?,
        headers: [String: String] = [:],
        transport: any WebSocketTransport = URLSessionWebSocketTransport(),
        backoff: WebSocketBackoff = .default,
        logger: Logger = Logger(label: "com.funico.server-foundation.websocket")
    ) {
        self.connectionURL = connectionURL
        self.headers = headers
        self.transport = transport
        self.backoff = backoff
        self.logger = logger
    }

    /// Connects to a fixed URL.
    ///
    /// - Parameters:
    ///   - url: the base URL. Its scheme decides `ws` versus `wss`.
    ///   - headers: sent on the upgrade request. Put the bearer token here.
    ///   - transport: how connections are opened.
    ///   - backoff: how long to wait between attempts.
    ///   - logger: where drops and retries are reported.
    public init(
        url: URL,
        headers: [String: String] = [:],
        transport: any WebSocketTransport = URLSessionWebSocketTransport(),
        backoff: WebSocketBackoff = .default,
        logger: Logger = Logger(label: "com.funico.server-foundation.websocket")
    ) {
        self.init(
            connectionURL: { url },
            headers: headers,
            transport: transport,
            backoff: backoff,
            logger: logger
        )
    }

    /// Every message, across every reconnect.
    ///
    /// The stream does not end when the connection drops — that is the entire point. It ends
    /// when ``close()`` is called, when the task is cancelled, or when `connectionURL`
    /// returns `nil`.
    public func events() -> AsyncStream<WebSocketEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1024)) { continuation in
            let pump = Task { await self.run(yielding: continuation) }
            self.pump = pump

            continuation.onTermination = { _ in pump.cancel() }
        }
    }

    /// Just the messages, for callers that do not care about connection transitions.
    public func messages() -> AsyncStream<WebSocketMessage> {
        let events = events()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1024)) { continuation in
            Task {
                for await event in events {
                    if case .message(let message) = event {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
        }
    }

    public func close() {
        pump?.cancel()
        pump = nil
    }

    private func run(yielding continuation: AsyncStream<WebSocketEvent>.Continuation) async {
        var attempt = 0

        while !Task.isCancelled {
            guard let baseURL = await connectionURL() else {
                continuation.finish()
                return
            }
            guard let url = baseURL.webSocketURL else {
                logger.error("Cannot open a WebSocket to \(baseURL.scheme ?? "?")://…")
                continuation.finish()
                return
            }

            var request = URLRequest(url: url)
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }

            do {
                let connection = try await transport.connect(to: request)

                // Only reset once a frame has actually arrived. Resetting on connect turns a
                // server that accepts and immediately drops into a hot reconnect loop.
                var hasReceived = false
                continuation.yield(.connected)

                defer { Task { await connection.close() } }

                while !Task.isCancelled {
                    let message = try await connection.receive()

                    if !hasReceived {
                        hasReceived = true
                        attempt = 0
                    }
                    continuation.yield(.message(message))
                }

                return
            } catch {
                if Task.isCancelled { break }

                let delay = backoff.delay(forAttempt: attempt)
                attempt += 1

                logger.warning("WebSocket dropped, retrying in \(delay): \(error)")
                continuation.yield(.disconnected(error: String(describing: error), retryingIn: delay))

                do {
                    try await Task.sleep(for: delay)
                } catch {
                    break
                }
            }
        }

        continuation.finish()
    }
}
