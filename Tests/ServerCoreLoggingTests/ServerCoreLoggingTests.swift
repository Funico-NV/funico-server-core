//
//  ServerCoreLoggingTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Testing
import Foundation
import Logging
import ServerCore
@testable import ServerCoreLogging

private func makeLog(_ message: String, level: Logger.Level = .info) -> FNCLog {
    FNCLog(
        level: level,
        message: "\(message)",
        metadata: nil,
        source: "Tests",
        file: #file,
        function: #function,
        line: #line
    )
}

// MARK: - FNCLog

@Test func fncLogEncodesTheKeysTheShippedAppDecodes() throws {
    let data = try JSONEncoder().encode(makeLog("hello"))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    // The iOS build in the App Store decodes exactly these. Renaming one is a silent
    // breakage: the log list just stops populating.
    #expect(Set(json.keys) == ["timestamp", "level", "message", "source", "file", "function", "line"])
    #expect(json["message"] as? String == "hello")
    #expect(json["level"] as? String == "info")
}

@Test func fncLogTimestampKeepsTheExistingDisplayFormat() throws {
    let log = FNCLog(
        date: Date(timeIntervalSince1970: 1_770_000_000),
        level: .info, message: "x", metadata: nil,
        source: "Tests", file: #file, function: #function, line: #line
    )

    // "yyyy-MM-dd HH:mm:ss+SSS" — a space, and a literal "+" before the milliseconds.
    // Unusual, but it is what renders in the app today.
    #expect(log.timestamp.wholeMatch(of: /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{3}/) != nil)
}

@Test func fncLogRoundTripsMetadata() throws {
    let log = FNCLog(
        level: .warning,
        message: "with metadata",
        metadata: ["server": .string("invoices"), "attempt": .stringConvertible(3)],
        source: "Tests", file: #file, function: #function, line: #line
    )

    let decoded = try JSONDecoder().decode(FNCLog.self, from: try JSONEncoder().encode(log))

    #expect(decoded.metadata?["server"] == .string("invoices"))
    // `stringConvertible` only ever had its description written, so it returns as one
    // wrapping a String rather than the original Int.
    #expect(decoded.metadata?["attempt"]?.description == "3")
}

@Test func fncLogRoundTripsNestedMetadata() throws {
    let log = FNCLog(
        level: .error,
        message: "nested",
        metadata: ["ctx": .dictionary(["k": .string("v")]), "list": .array([.string("a")])],
        source: "Tests", file: #file, function: #function, line: #line
    )

    let decoded = try JSONDecoder().decode(FNCLog.self, from: try JSONEncoder().encode(log))

    #expect(decoded.metadata?["ctx"] == .dictionary(["k": .string("v")]))
    #expect(decoded.metadata?["list"] == .array([.string("a")]))
}

// MARK: - LogStorage

@Test func logStorageKeepsOrderAndContents() {
    let storage = LogStorage(capacity: 10)
    for i in 0..<5 { storage.append(makeLog("line \(i)")) }

    #expect(storage.count == 5)
    #expect(storage.all().map(\.message.description) == (0..<5).map { "line \($0)" })
}

@Test func logStorageDropsTheOldestPastCapacity() {
    let storage = LogStorage(capacity: 3)
    for i in 0..<5 { storage.append(makeLog("line \(i)")) }

    #expect(storage.count == 3)
    #expect(storage.all().map(\.message.description) == ["line 2", "line 3", "line 4"])
}

@Test func logStorageStaysBoundedUnderSustainedAppends() {
    let storage = LogStorage(capacity: 100)
    for i in 0..<10_000 { storage.append(makeLog("line \(i)")) }

    #expect(storage.count == 100)
    #expect(storage.all().first?.message.description == "line 9900")
    #expect(storage.all().last?.message.description == "line 9999")
}

@Test func logStorageStreamsLiveAppendsInOrder() async {
    let storage = LogStorage(capacity: 100)
    var received: [String] = []

    let stream = storage.stream()
    for i in 0..<20 { storage.append(makeLog("line \(i)")) }

    var iterator = stream.makeAsyncIterator()
    for _ in 0..<20 {
        if let log = await iterator.next() { received.append(log.message.description) }
    }

    // Ordering is the point. The original appended via an unstructured `Task` per line,
    // which has no ordering guarantee at all.
    #expect(received == (0..<20).map { "line \($0)" })
}

@Test func logStorageCanReplayWhatItAlreadyHas() async {
    let storage = LogStorage(capacity: 100)
    for i in 0..<3 { storage.append(makeLog("old \(i)")) }

    var iterator = storage.stream(replayingExisting: true).makeAsyncIterator()
    storage.append(makeLog("new"))

    var received: [String] = []
    for _ in 0..<4 {
        if let log = await iterator.next() { received.append(log.message.description) }
    }

    // Replayed history and live traffic arrive on one ordered stream, with no gap and no
    // duplicate at the boundary.
    #expect(received == ["old 0", "old 1", "old 2", "new"])
}

@Test func logStorageStopsFeedingATerminatedSubscriber() async {
    let storage = LogStorage(capacity: 10)

    do {
        let stream = storage.stream()
        var iterator = stream.makeAsyncIterator()
        storage.append(makeLog("one"))
        _ = await iterator.next()
    }

    // Give the termination handler a chance to run before asserting deregistration.
    try? await Task.sleep(for: .milliseconds(50))
    storage.append(makeLog("two"))

    #expect(storage.count == 2)
}

// MARK: - MemoryLogHandler

@Test func memoryLogHandlerStoresWhatIsLogged() {
    let storage = LogStorage(capacity: 10)
    var logger = Logger(label: "test") { _ in
        MemoryLogHandler(storage: storage, echoesToStandardOutput: false)
    }
    logger.logLevel = .trace

    logger.info("first")
    logger.error("second")

    let stored = storage.all()
    #expect(stored.map(\.message.description) == ["first", "second"])
    #expect(stored.map(\.level) == [.info, .error])
}

@Test func memoryLogHandlerMergesHandlerAndCallSiteMetadata() {
    let storage = LogStorage(capacity: 10)
    var logger = Logger(label: "test") { _ in
        MemoryLogHandler(storage: storage, echoesToStandardOutput: false)
    }
    logger[metadataKey: "server"] = .string("invoices")

    logger.info("hello", metadata: ["request": .string("abc")])

    let metadata = storage.all().first?.metadata
    // The original forwarded only the call-site metadata, silently dropping anything set
    // on the logger itself.
    #expect(metadata?["server"] == .string("invoices"))
    #expect(metadata?["request"] == .string("abc"))
}

@Test func callSiteMetadataWinsOverHandlerMetadata() {
    let storage = LogStorage(capacity: 10)
    var logger = Logger(label: "test") { _ in
        MemoryLogHandler(storage: storage, echoesToStandardOutput: false)
    }
    logger[metadataKey: "scope"] = .string("handler")

    logger.info("hello", metadata: ["scope": .string("call site")])

    #expect(storage.all().first?.metadata?["scope"] == .string("call site"))
}

// MARK: - ServerEventEnvelope

@Test func envelopeRoundTripsEveryPayload() throws {
    let date = Date(timeIntervalSince1970: 1_770_000_000)
    let payloads: [ServerEventEnvelope.Payload] = [
        .state(.maintenance(since: date)),
        .jobState(job: "Process", state: .finished(.failed("nope"), on: date)),
        .jobs([ServerJobDescriptor(job: "Lookup", title: "Lookup", capabilities: [.start])]),
        .log(makeLog("streamed"))
    ]

    for payload in payloads {
        let envelope = ServerEventEnvelope(sequence: 7, serverID: "invoices", payload: payload)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ServerEventEnvelope.self, from: data)

        #expect(decoded.sequence == 7)
        #expect(decoded.serverID == "invoices")
        #expect(decoded.version == ServerEventEnvelope.currentVersion)
    }
}

@Test func envelopeCarriesTheJobResultThroughTheWire() throws {
    let envelope = ServerEventEnvelope(
        sequence: 1,
        serverID: "invoices",
        payload: .jobState(job: "Process", state: .finished(.failed("db down"), on: Date()))
    )

    let decoded = try JSONDecoder().decode(
        ServerEventEnvelope.self, from: try JSONEncoder().encode(envelope)
    )

    guard case .jobState(let job, let state) = decoded.payload else {
        Issue.record("payload did not survive the round trip")
        return
    }
    #expect(job == "Process")
    #expect(state.failureReason == "db down")
}

@Test func envelopeReportsTheTopicItBelongsTo() {
    let date = Date()

    #expect(ServerEventEnvelope(sequence: 1, serverID: "s", payload: .state(.online)).topic == .state)
    #expect(ServerEventEnvelope(sequence: 2, serverID: "s", payload: .jobs([])).topic == .jobs)
    #expect(ServerEventEnvelope(
        sequence: 3, serverID: "s", payload: .jobState(job: "J", state: .idle(since: date))
    ).topic == .jobs)
    #expect(ServerEventEnvelope(sequence: 4, serverID: "s", payload: .log(makeLog("x"))).topic == .log)
}
