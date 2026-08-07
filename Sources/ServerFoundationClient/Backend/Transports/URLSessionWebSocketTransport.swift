//
//  URLSessionWebSocketTransport.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real transport, on `URLSessionWebSocketTask`.
public struct URLSessionWebSocketTransport: WebSocketTransport {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(to request: URLRequest) async throws -> any WebSocketConnection {
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

private struct URLSessionWebSocketConnection: WebSocketConnection {

    // `URLSessionWebSocketTask` is thread-safe for these operations but is not marked
    // `Sendable`, so the unchecked box is confined to this file.
    private let box: TaskBox

    init(task: URLSessionWebSocketTask) {
        self.box = TaskBox(task: task)
    }

    func receive() async throws -> WebSocketMessage {
        switch try await box.task.receive() {
        case .string(let text): .text(text)
        case .data(let data): .binary(data)
        @unknown default: throw WebSocketError.transport("Unknown frame type")
        }
    }

    func send(_ message: WebSocketMessage) async throws {
        switch message {
        case .text(let text): try await box.task.send(.string(text))
        case .binary(let data): try await box.task.send(.data(data))
        }
    }

    func close() async {
        box.task.cancel(with: .normalClosure, reason: nil)
    }

    final class TaskBox: @unchecked Sendable {
        let task: URLSessionWebSocketTask
        init(task: URLSessionWebSocketTask) { self.task = task }
    }
}
