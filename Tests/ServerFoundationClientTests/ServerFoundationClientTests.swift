//
//  ServerFoundationClientTests.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Testing
import Foundation
@testable import ServerFoundationClient

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Scheme derivation

@Test func derivesTheWebSocketSchemeFromTheBaseURL() throws {
    #expect(URL(string: "http://10.0.0.5:5910")?.webSocketURL?.absoluteString == "ws://10.0.0.5:5910")
    #expect(URL(string: "https://box.ts.net")?.webSocketURL?.absoluteString == "wss://box.ts.net")
    #expect(URL(string: "ws://10.0.0.5")?.webSocketURL?.absoluteString == "ws://10.0.0.5")
    #expect(URL(string: "wss://box.ts.net")?.webSocketURL?.absoluteString == "wss://box.ts.net")
}

@Test func refusesToGuessAtAnUnknownScheme() {
    #expect(URL(string: "ftp://box.ts.net")?.webSocketURL == nil)
    #expect(URL(string: "file:///tmp/x")?.webSocketURL == nil)
}

@Test func httpsBecomesWSSRatherThanTheHardcodedWS() throws {
    // The specific regression this replaces: all three modifiers in InvoicesAPI 1.2.5
    // string-build "ws://" + host, so anything behind TLS fails to connect at all.
    let url = try #require(URL(string: "https://box.ts.net:5910")?.webSocketURL(path: "server", "state"))

    #expect(url.absoluteString == "wss://box.ts.net:5910/server/state")
}

// MARK: - Backoff

@Test func backoffGrowsExponentiallyAndThenStops() {
    let backoff = WebSocketBackoff(
        initialDelay: .seconds(1), maximumDelay: .seconds(60), multiplier: 2
    )

    #expect(backoff.ceiling(forAttempt: 0).seconds == 1)
    #expect(backoff.ceiling(forAttempt: 1).seconds == 2)
    #expect(backoff.ceiling(forAttempt: 3).seconds == 8)
    #expect(backoff.ceiling(forAttempt: 20).seconds == 60)   // capped, not astronomical
}

@Test func fullJitterSpreadsRetriesAcrossTheWholeWindow() {
    let backoff = WebSocketBackoff(initialDelay: .seconds(1), maximumDelay: .seconds(60))

    // Full jitter draws from 0...ceiling. Retrying at exactly the ceiling is what
    // synchronises every client into a thundering herd after a server restart.
    #expect(backoff.delay(forAttempt: 3, jitter: { 0 }).seconds == 0)
    #expect(backoff.delay(forAttempt: 3, jitter: { 1 }).seconds == 8)
    #expect(backoff.delay(forAttempt: 3, jitter: { 0.5 }).seconds == 4)
}

@Test func jitterOutsideTheUnitRangeIsClamped() {
    let backoff = WebSocketBackoff(initialDelay: .seconds(1), maximumDelay: .seconds(60))

    #expect(backoff.delay(forAttempt: 3, jitter: { -5 }).seconds == 0)
    #expect(backoff.delay(forAttempt: 3, jitter: { 99 }).seconds == 8)
}

// MARK: - A transport that can be scripted

private final class ScriptedTransport: WebSocketTransport, @unchecked Sendable {

    enum Outcome: Sendable {
        case refuseConnection
        case deliver([WebSocketMessage], thenDrop: Bool)
    }

    private let lock = NSLock()
    private var script: [Outcome]
    private var requests: [URLRequest] = []

    init(script: [Outcome]) {
        self.script = script
    }

    var attemptCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    // Synchronous, because `NSLock.lock()` cannot be called from an async context.
    private func recordAndTakeNextOutcome(for request: URLRequest) -> Outcome {
        lock.lock()
        defer { lock.unlock() }

        requests.append(request)
        return script.isEmpty ? .deliver([], thenDrop: false) : script.removeFirst()
    }

    func connect(to request: URLRequest) async throws -> any WebSocketConnection {
        switch recordAndTakeNextOutcome(for: request) {
        case .refuseConnection:
            throw WebSocketError.transport("refused")
        case .deliver(let messages, let thenDrop):
            return ScriptedConnection(messages: messages, dropsAfterwards: thenDrop)
        }
    }
}

private final class ScriptedConnection: WebSocketConnection, @unchecked Sendable {

    private let lock = NSLock()
    private var pending: [WebSocketMessage]
    private let dropsAfterwards: Bool

    init(messages: [WebSocketMessage], dropsAfterwards: Bool) {
        self.pending = messages
        self.dropsAfterwards = dropsAfterwards
    }

    private func takeNextMessage() -> WebSocketMessage? {
        lock.lock()
        defer { lock.unlock() }

        return pending.isEmpty ? nil : pending.removeFirst()
    }

    func receive() async throws -> WebSocketMessage {
        if let next = takeNextMessage() { return next }
        if dropsAfterwards { throw WebSocketError.transport("dropped") }

        // Idle but healthy: suspend until cancelled, the way a real quiet socket does.
        try await Task.sleep(for: .seconds(60))
        throw WebSocketError.closed
    }

    func send(_ message: WebSocketMessage) async throws {}

    func close() async {}
}

// MARK: - Reconnection

private let fastBackoff = WebSocketBackoff(
    initialDelay: .milliseconds(1), maximumDelay: .milliseconds(5)
)

@Test func survivesARefusedConnectionAndKeepsRetrying() async throws {
    let transport = ScriptedTransport(script: [
        .refuseConnection,
        .refuseConnection,
        .deliver([.text("finally")], thenDrop: false)
    ])
    let socket = ResilientWebSocket(
        url: URL(string: "http://10.0.0.5:5910/log")!,
        transport: transport,
        backoff: fastBackoff
    )

    var received: [String] = []
    for await event in await socket.events() {
        if case .message(let message) = event, let text = message.text {
            received.append(text)
            break
        }
    }

    // The behaviour being replaced gives up permanently on the first failure.
    #expect(received == ["finally"])
    #expect(transport.attemptCount == 3)
}

@Test func resumesAfterALiveConnectionDrops() async throws {
    let transport = ScriptedTransport(script: [
        .deliver([.text("before")], thenDrop: true),
        .deliver([.text("after")], thenDrop: false)
    ])
    let socket = ResilientWebSocket(
        url: URL(string: "http://10.0.0.5:5910/log")!,
        transport: transport,
        backoff: fastBackoff
    )

    var received: [String] = []
    for await event in await socket.events() {
        if case .message(let message) = event, let text = message.text {
            received.append(text)
            if received.count == 2 { break }
        }
    }

    #expect(received == ["before", "after"])
}

@Test func reportsTheDisconnectionSoAViewCanShowIt() async throws {
    let transport = ScriptedTransport(script: [
        .deliver([], thenDrop: true),
        .deliver([.text("back")], thenDrop: false)
    ])
    let socket = ResilientWebSocket(
        url: URL(string: "http://10.0.0.5:5910/log")!,
        transport: transport,
        backoff: fastBackoff
    )

    var observed: [String] = []
    for await event in await socket.events() {
        switch event {
        case .connected: observed.append("connected")
        case .disconnected(_, let retryingIn):
            observed.append("disconnected")
            #expect(retryingIn.seconds >= 0)
        case .message:
            observed.append("message")
        }
        if observed.contains("message") { break }
    }

    // A view can render "reconnecting…" instead of going quietly stale, which is what the
    // current modifiers do.
    #expect(observed == ["connected", "disconnected", "connected", "message"])
}

@Test func rebuildsTheURLOnEveryAttemptSoAResumeCanCarrySince() async throws {
    let transport = ScriptedTransport(script: [
        .deliver([], thenDrop: true),
        .deliver([.text("resumed")], thenDrop: false)
    ])

    // The agent's stream is resumable with ?since=<sequence>; that only works if the URL is
    // recomputed per attempt rather than captured once at construction.
    let sequence = LockedCounter()
    let socket = ResilientWebSocket(
        connectionURL: { URL(string: "http://10.0.0.5:5910/events?since=\(sequence.next())") },
        transport: transport,
        backoff: fastBackoff
    )

    for await event in await socket.events() {
        if case .message = event { break }
    }

    #expect(transport.attemptCount == 2)
    #expect(transport.lastRequest?.url?.query == "since=2")
}

@Test func sendsCredentialsAsAHeaderAndNeverInTheQueryString() async throws {
    let transport = ScriptedTransport(script: [.deliver([.text("hi")], thenDrop: false)])
    let socket = ResilientWebSocket(
        url: URL(string: "https://box.ts.net/events")!,
        headers: ["Authorization": "Bearer secret-token"],
        transport: transport,
        backoff: fastBackoff
    )

    for await event in await socket.events() {
        if case .message = event { break }
    }

    let request = try #require(transport.lastRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")

    // A token in the query string lands in server access logs and proxy caches.
    let url = try #require(request.url?.absoluteString)
    #expect(url.contains("secret-token") == false)
    #expect(url.hasPrefix("wss://"))
}

@Test func stopsWhenTheURLProviderSaysThereIsNowhereToConnect() async {
    let transport = ScriptedTransport(script: [])
    let socket = ResilientWebSocket(
        connectionURL: { nil },
        transport: transport,
        backoff: fastBackoff
    )

    var eventCount = 0
    for await _ in await socket.events() { eventCount += 1 }

    // Finishes rather than spinning — the caller has said there is no server to reach.
    #expect(eventCount == 0)
    #expect(transport.attemptCount == 0)
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
