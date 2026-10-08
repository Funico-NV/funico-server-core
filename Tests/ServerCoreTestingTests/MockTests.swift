//
//  MockTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Testing
import Foundation
import ServerCore
import ServerCoreTesting

// The mocks stand in for the agent's real backends in other packages' tests, so they have to
// honour the same contracts: refuse unlisted services, page logs by cursor, never touch
// production before activation.

private let invoices = ServiceDescriptor(id: "invoices", displayName: "Invoices", backend: .systemd)

@Test func theBackendTracksOperationsAndRefusesUnlistedServices() async throws {
    let backend = MockServiceBackend(services: [invoices])

    #expect(try await backend.status(of: "invoices").activeState == .inactive)
    try await backend.perform(.restart, on: "invoices")
    #expect(try await backend.status(of: "invoices").activeState == .active)
    try await backend.perform(.stop, on: "invoices")
    #expect(try await backend.status(of: "invoices").activeState == .inactive)

    #expect(await backend.performed == [.init(.restart, "invoices"), .init(.stop, "invoices")])

    await #expect(throws: ServerCoreError(.unknownService, "sshd is not listed on this host")) {
        try await backend.perform(.stop, on: "sshd")
    }
}

@Test func theBackendFailsOnRequestAndRecovers() async throws {
    let backend = MockServiceBackend(services: [invoices])
    let failure = ServerCoreError(.backendFailure, "Access denied")

    await backend.fail("invoices", with: failure)
    await #expect(throws: failure) { try await backend.perform(.start, on: "invoices") }

    await backend.recover("invoices")
    try await backend.perform(.start, on: "invoices")
    #expect(try await backend.services() == [invoices])
}

private func entry(_ message: String, _ priority: LogPriority = .info, at seconds: TimeInterval = 0) -> LogEntry {
    LogEntry(timestamp: Date(timeIntervalSince1970: seconds), priority: priority, message: message, service: "invoices")
}

@Test func theLogSourceAppliesQueries() async throws {
    let logs = MockLogSource(entries: [
        entry("started", at: 1), entry("DB slow", .warning, at: 2), entry("db down", .error, at: 3),
    ])

    #expect(try await logs.entries(of: "invoices", matching: LogQuery()).map(\.message) == ["started", "DB slow", "db down"])
    #expect(try await logs.entries(of: "invoices", matching: LogQuery(minimumPriority: .warning)).count == 2)
    #expect(try await logs.entries(of: "invoices", matching: LogQuery(contains: "db")).count == 2)
    #expect(try await logs.entries(of: "invoices", matching: LogQuery(since: Date(timeIntervalSince1970: 3))).map(\.message) == ["db down"])
    #expect(try await logs.entries(of: "invoices", matching: LogQuery(limit: 1)).map(\.message) == ["db down"])
    #expect(try await logs.entries(of: "scheduler", matching: LogQuery()).isEmpty)
}

@Test func theLogSourcePagesByCursorWithoutGapsOrRepeats() async throws {
    let logs = MockLogSource(entries: (0..<5).map { entry("line \($0)") })

    let first = try await logs.entries(of: "invoices", matching: LogQuery(limit: 2))
    let all = try await logs.entries(of: "invoices", matching: LogQuery())
    let firstPage = try await logs.entries(of: "invoices", matching: LogQuery(afterCursor: all[0].cursor, limit: 2))

    #expect(first.map(\.message) == ["line 3", "line 4"])
    #expect(firstPage.map(\.message) == ["line 1", "line 2"])

    await #expect(throws: ServerCoreError.self) {
        try await logs.entries(of: "invoices", matching: LogQuery(afterCursor: "nowhere"))
    }
}

@Test func followingDeliversTheBacklogAfterACursorThenNewEntries() async throws {
    let logs = MockLogSource(entries: [entry("old"), entry("missed")])
    let cursor = try await logs.entries(of: "invoices", matching: LogQuery())[0].cursor

    let stream = try await logs.follow("invoices", after: cursor)
    await logs.append(entry("new"))
    await logs.append(LogEntry(timestamp: Date(), priority: .info, message: "other", service: "scheduler"))

    var received: [String] = []
    for try await entry in stream {
        received.append(entry.message)
        if received.count == 2 { break }
    }
    #expect(received == ["missed", "new"])
}

private let artifact = ReleaseArtifact(
    platform: .linuxX86_64,
    archiveURL: URL(string: "https://example.com/a.tar.gz")!,
    checksumURL: URL(string: "https://example.com/a.tar.gz.sha256")!,
    signatureURL: URL(string: "https://example.com/a.tar.gz.sig")!
)

private final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [DeploymentStage] = []

    func record(_ stage: DeploymentStage) { lock.withLock { stages.append(stage) } }
    var recorded: [DeploymentStage] { lock.withLock { stages } }
}

@Test func theExecutorStagesActivatesAndRollsBack() async throws {
    let executor = MockDeploymentExecutor(currentVersions: ["invoices": "1.5.2"])
    let request = DeploymentRequest(deployment: "d1", service: "invoices", version: "1.6.0", artifact: artifact)
    let stages = StageLog()

    let staged = try await executor.stage(request) { stage, _ in stages.record(stage) }
    #expect(stages.recorded == [.downloading, .verifying, .extracting, .preflight])
    #expect(stages.recorded.allSatisfy { !$0.touchesProduction })
    try staged.manifest.validate()
    #expect(await executor.currentVersion(of: "invoices") == "1.5.2")

    try await executor.activate(staged)
    #expect(await executor.currentVersion(of: "invoices") == "1.6.0")

    #expect(try await executor.rollback("invoices") == "1.5.2")
    #expect(await executor.currentVersion(of: "invoices") == "1.5.2")
}

@Test func theExecutorFailsWhereItIsToldTo() async throws {
    let executor = MockDeploymentExecutor(currentVersions: ["invoices": "1.5.2"])
    let request = DeploymentRequest(deployment: "d1", service: "invoices", version: "1.6.0", artifact: artifact)

    await executor.failAt(.verifying)
    do {
        _ = try await executor.stage(request) { _, _ in }
        Issue.record("expected verification to fail")
    } catch let error as ServerCoreError {
        #expect(error.code == .verificationFailed)
    }
    #expect(await executor.currentVersion(of: "invoices") == "1.5.2")

    await executor.failAt(.activating)
    let staged = try await executor.stage(request) { _, _ in }
    await #expect(throws: ServerCoreError.self) { try await executor.activate(staged) }
    await executor.discard(staged)
    #expect(await executor.discarded == [staged])

    await #expect(throws: ServerCoreError.self) { try await executor.rollback("invoices") }
    await #expect(throws: ServerCoreError.self) {
        _ = try await executor.stage(DeploymentRequest(deployment: "d2", service: "sshd", version: "1", artifact: artifact)) { _, _ in }
    }
}

@Test func theHealthProbeAnswersReadyUnlessTold() async {
    let probe = MockHealthProbe()
    #expect(await probe.check("invoices", expecting: "1.6.0") == HealthCheckResult(isReady: true, reportedVersion: "1.6.0"))

    let stuck = HealthCheckResult(isReady: false, reportedVersion: "1.5.2", detail: "old binary")
    await probe.setResult(stuck, for: "invoices")
    #expect(await probe.check("invoices", expecting: "1.6.0") == stuck)
    #expect(await probe.checkCounts["invoices"] == 2)
}

@Test func theSamplerAndReleaseSourceReturnTheirFixtures() async throws {
    let sample = try await MockResourceSampler().sample()
    #expect(sample.memoryTotalBytes == 8 << 30)

    let release = ReleaseInfo(repository: "Funico-NV/x", tag: "v1", version: "1", eligibility: .noArtifact)
    let source = MockReleaseSource(releases: ["Funico-NV/x": [release]])
    #expect(try await source.releases(of: "Funico-NV/x", for: .linuxX86_64) == [release])
    #expect(try await source.releases(of: "Funico-NV/y", for: .linuxX86_64).isEmpty)
}
