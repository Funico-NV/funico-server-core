//
//  WebSocketMessage.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// A frame in either direction.
public enum WebSocketMessage: Sendable, Hashable {

    case text(String)
    case binary(Data)

    /// The text of this message, decoding a binary frame as UTF-8.
    ///
    /// Servers are inconsistent about which frame type they use for JSON, so a client that
    /// only handles `.text` silently ignores half of them.
    public var text: String? {
        switch self {
        case .text(let text): text
        case .binary(let data): String(data: data, encoding: .utf8)
        }
    }
}

/// Why a resilient socket gave up or reconnected.
public enum WebSocketEvent: Sendable {

    case connected
    case message(WebSocketMessage)

    /// The connection dropped and a reconnect is scheduled after `retryingIn`.
    case disconnected(error: String, retryingIn: Duration)
}
