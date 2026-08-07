//
//  WebSocketTransport.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// One live WebSocket connection.
public protocol WebSocketConnection: Sendable {

    /// Suspends until the next frame arrives, or throws when the connection is gone.
    func receive() async throws -> WebSocketMessage

    func send(_ message: WebSocketMessage) async throws

    func close() async
}

/// Opens connections.
///
/// A protocol rather than a direct `URLSession` call so that reconnection behaviour is
/// testable. Proving backoff and recovery against a real server means starting, killing and
/// restarting one inside a unit test; against a fake transport that fails a scripted number
/// of times, it is deterministic and takes milliseconds.
public protocol WebSocketTransport: Sendable {

    func connect(to request: URLRequest) async throws -> any WebSocketConnection
}

public enum WebSocketError: Error, Sendable, Hashable {

    /// The base URL had a scheme that cannot carry a WebSocket.
    case unsupportedScheme(String)

    /// The socket closed without an error — normal for a server shutdown.
    case closed

    case transport(String)
}
