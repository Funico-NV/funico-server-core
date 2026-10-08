//
//  AgentModelTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Testing
import Foundation
import ServerCore

// Every model here crosses a process boundary — agent to Manager, Manager to app or browser — so
// these tests pin the wire shape, not just that Swift can read back what Swift wrote.

private let fixedDate = Date(timeIntervalSince1970: 1_770_000_000.25)

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try AgentProtocol.encoder.encode(value)
    return try AgentProtocol.decoder.decode(T.self, from: data)
}

private func json(_ value: some Encodable) throws -> [String: Any] {
    let data = try AgentProtocol.encoder.encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let artifact = ReleaseArtifact(
    platform: .linuxX86_64,
    archiveURL: URL(string: "https://example.com/invoices-1.6.0-linux-x86_64.tar.gz")!,
    checksumURL: URL(string: "https://example.com/invoices-1.6.0-linux-x86_64.tar.gz.sha256")!,
    signatureURL: URL(string: "https://example.com/invoices-1.6.0-linux-x86_64.tar.gz.sig")!,
    size: 12_345
)

private let hash = String(repeating: "ab", count: 32)

private func manifest(
    files: [String: String] = ["bin/Invoices": hash, "lib/libAMSMB2.so": hash],
    entrypoint: String = "bin/Invoices",
    schema: Int = ArtifactManifest.currentSchema,
    healthPath: String? = "/health",
    configKeys: [String] = ["DATABASE_URL"]
) -> ArtifactManifest {
    ArtifactManifest(
        schema: schema,
        service: "invoices",
        version: "1.6.0",
        gitCommit: "4f2a",
        platform: .linuxX86_64,
        entrypoint: entrypoint,
        files: files,
        healthPath: healthPath,
        configKeys: configKeys
    )
}

// MARK: - Identifiers and errors

@Test func identifiersEncodeAsBareStrings() throws {
    let data = try AgentProtocol.encoder.encode([ServiceID("invoices")])
    #expect(String(decoding: data, as: UTF8.self) == #"["invoices"]"#)

    #expect(try roundTrip(ServerID("funapi-01")) == "funapi-01")
    #expect(try roundTrip(AgentID("agent-1")) == "agent-1")
    #expect(try roundTrip(DeploymentID("d1")) == "d1")
}

@Test func freshCommandAndDeploymentIDsAreUnique() {
    #expect(CommandID() != CommandID())
    #expect(DeploymentID() != DeploymentID())
}

@Test func errorsCarryAnOpenCodeAndSurviveAnUnknownOne() throws {
    let error = ServerCoreError(.unknownService, "nope")
    #expect(try roundTrip(error) == error)

    let fromTheFuture = Data(#"{"code":"quotaExceeded","message":"later"}"#.utf8)
    let decoded = try AgentProtocol.decoder.decode(ServerCoreError.self, from: fromTheFuture)
    #expect(decoded.code.rawValue == "quotaExceeded")
}

// MARK: - Services

@Test func anUnknownActiveStateDecodesAsUnknownRatherThanFailing() throws {
    let decoded = try AgentProtocol.decoder.decode([ServiceActiveState].self, from: Data(#"["active","exploding"]"#.utf8))
    #expect(decoded == [.active, .unknown])
}

@Test func runningStatesAreTheOnesADashboardShowsAsUp() {
    #expect(ServiceActiveState.active.isRunning)
    #expect(ServiceActiveState.activating.isRunning)
    #expect(!ServiceActiveState.failed.isRunning)
    #expect(!ServiceActiveState.inactive.isRunning)
}

@Test func anUnknownServiceOperationIsRefusedAtDecoding() {
    #expect(throws: DecodingError.self) {
        try AgentProtocol.decoder.decode(ServiceOperation.self, from: Data(#""reboot""#.utf8))
    }
}

@Test func serviceModelsRoundTrip() throws {
    let status = ServiceStatus(
        service: "invoices", activeState: .failed, subState: "auto-restart", since: fixedDate,
        mainPID: 42, restartCount: 3, lastExitStatus: 1, version: "1.5.2"
    )
    #expect(try roundTrip(status) == status)

    let descriptor = ServiceDescriptor(
        id: "invoices", displayName: "Invoices", backend: .systemd,
        unit: "funico-invoices.service", repository: "Funico-NV/funico-invoices-service", deploysEnabled: true
    )
    #expect(try roundTrip(descriptor) == descriptor)

    let resources = ServerResources(
        sampledAt: fixedDate, cpuUsage: 0.5, memoryUsedBytes: 1, memoryTotalBytes: 2,
        diskUsedBytes: 3, diskTotalBytes: 4, loadAverage: [1, 2, 3], uptime: 60
    )
    #expect(try roundTrip(resources) == resources)
}

// MARK: - Releases

@Test func releaseModelsRoundTrip() throws {
    let release = ReleaseInfo(
        repository: "Funico-NV/funico-invoices-service", tag: "v1.6.0", version: "1.6.0",
        publishedAt: fixedDate, notes: "Fixes", artifact: artifact, eligibility: .eligible
    )
    #expect(try roundTrip(release) == release)
    #expect(release.id == "Funico-NV/funico-invoices-service@v1.6.0")
    #expect(try roundTrip(manifest()) == manifest())
}

@Test func platformsPrintAsTheyAppearInAssetNames() {
    #expect(ArtifactPlatform.linuxX86_64.description == "linux-x86_64")
}

@Test func onlyEligibleReleasesAreEligible() {
    #expect(ReleaseEligibility.allCases.filter(\.isEligible) == [.eligible])
}

@Test func aWellFormedManifestValidates() throws {
    try manifest().validate()
    try manifest(healthPath: nil, configKeys: []).validate()
}

@Test(arguments: ["../etc/passwd", "/bin/sh", "bin//Invoices", "bin/./Invoices", "bin/../../x", "", "bin\\Invoices"])
func aManifestPathThatCouldEscapeTheReleaseIsRejected(path: String) {
    #expect(throws: ServerCoreError.self) {
        try manifest(files: [path: hash, "bin/Invoices": hash]).validate()
    }
}

@Test func aManifestIsRejectedForEachStructuralProblem() {
    let broken: [ArtifactManifest] = [
        manifest(schema: ArtifactManifest.currentSchema + 1),
        manifest(schema: 0),
        manifest(files: [:]),
        manifest(entrypoint: "bin/Missing"),
        manifest(files: ["bin/Invoices": "not-a-hash"]),
        manifest(healthPath: "health"),
        manifest(healthPath: "//evil.example/health"),
        manifest(healthPath: "/x?u=http://evil.example"),
        manifest(configKeys: ["1BAD"]),
        manifest(configKeys: ["HAS SPACE"]),
        manifest(configKeys: [""]),
    ]
    for manifest in broken {
        do {
            try manifest.validate()
            Issue.record("expected \(manifest) to be rejected")
        } catch let error as ServerCoreError {
            #expect(error.code == .invalidManifest)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}

// MARK: - Deployments

@Test func productionIsTouchedFromActivationOn() {
    #expect(!DeploymentStage.preflight.touchesProduction)
    #expect(DeploymentStage.activating.touchesProduction)
    #expect(DeploymentStage.checkingReadiness.touchesProduction)
    #expect(DeploymentStage.downloading < DeploymentStage.committed)
}

@Test func deploymentStatesEncodeFlat() throws {
    let error = ServerCoreError(.verificationFailed, "bad signature")
    let object = try json(DeploymentState.failed(at: .verifying, error: error))

    #expect(object["status"] as? String == "failed")
    #expect(object["stage"] as? String == "verifying")
    #expect((object["error"] as? [String: Any])?["code"] as? String == "verificationFailed")
}

@Test func everyDeploymentStateRoundTrips() throws {
    let error = ServerCoreError(.notReady, "health check timed out")
    let states: [DeploymentState] = [
        .pending, .running(.downloading), .succeeded, .failed(at: .preflight, error: error),
        .cancelled, .rolledBack(from: .checkingReadiness, error: error),
        .rollbackFailed(from: .restarting, error: error),
    ]
    for state in states {
        #expect(try roundTrip(state) == state)
    }
    #expect(states.filter(\.isTerminal).count == 5)
    #expect(DeploymentState.rolledBack(from: .restarting, error: error).error == error)
}

@Test func deploymentRecordsRoundTrip() throws {
    let record = DeploymentRecord(
        id: "d1", server: "funapi-01", service: "invoices", fromVersion: "1.5.2", toVersion: "1.6.0",
        requestedBy: "user-1", requestedAt: fixedDate, updatedAt: fixedDate, state: .running(.verifying)
    )
    #expect(try roundTrip(record) == record)
}

// MARK: - Logs

@Test func logPrioritiesOrderBySeverityAndMapToSyslog() {
    #expect(LogPriority.error > .warning)
    #expect(LogPriority.debug < .info)
    #expect(LogPriority.emergency.syslogLevel == 0)
    #expect(LogPriority(syslogLevel: 3) == .error)
    #expect(LogPriority(syslogLevel: 8) == nil)
    for priority in LogPriority.allCases {
        #expect(LogPriority(syslogLevel: priority.syslogLevel) == priority)
    }
}

@Test func logQueryLimitsAreClamped() {
    #expect(LogQuery().effectiveLimit == LogQuery.defaultLimit)
    #expect(LogQuery(limit: 0).effectiveLimit == 1)
    #expect(LogQuery(limit: 1_000_000).effectiveLimit == LogQuery.maximumLimit)
}

@Test func logModelsRoundTrip() throws {
    let entry = LogEntry(
        cursor: "s=1", timestamp: fixedDate, priority: .warning, message: "slow",
        service: "invoices", pid: 7, fields: ["SYSLOG_IDENTIFIER": "Invoices"]
    )
    #expect(try roundTrip(entry) == entry)

    let query = LogQuery(since: fixedDate, until: fixedDate, afterCursor: "s=1", minimumPriority: .error, contains: "db", limit: 10)
    #expect(try roundTrip(query) == query)
}

@Test func protocolDatesKeepFractionalSeconds() throws {
    let entry = LogEntry(timestamp: fixedDate, priority: .info, message: "x", service: "invoices")
    #expect(try roundTrip(entry).timestamp == fixedDate)

    let object = try json(entry)
    #expect((object["timestamp"] as? String)?.hasSuffix(".250Z") == true)
}

// MARK: - Agent protocol

private let everyCommand: [AgentCommand] = [
    .listServices,
    .status(service: nil),
    .status(service: "invoices"),
    .perform(.restart, service: "invoices"),
    .queryLogs(service: "invoices", query: LogQuery(minimumPriority: .error)),
    .followLogs(service: "invoices", afterCursor: "s=1"),
    .followLogs(service: "invoices", afterCursor: nil),
    .stopFollowingLogs(service: "invoices"),
    .deploy(DeploymentRequest(deployment: "d1", service: "invoices", version: "1.6.0", artifact: artifact)),
    .rollback(service: "invoices", deployment: "d2"),
    .cancel("c1"),
]

@Test func everyCommandRoundTrips() throws {
    for command in everyCommand {
        #expect(try roundTrip(command) == command)
    }
}

@Test func commandsEncodeFlatWithAKind() throws {
    let object = try json(AgentCommand.perform(.restart, service: "invoices"))
    #expect(object as NSDictionary == ["kind": "perform", "operation": "restart", "service": "invoices"] as NSDictionary)
}

@Test func anUnknownCommandKindDecodesAsUnsupportedAndCannotBeSent() throws {
    let decoded = try AgentProtocol.decoder.decode(AgentCommand.self, from: Data(#"{"kind":"shell","argv":["rm","-rf","/"]}"#.utf8))
    #expect(decoded == .unsupported(kind: "shell"))
    #expect(decoded.service == nil)
    #expect(throws: EncodingError.self) { try AgentProtocol.encoder.encode(decoded) }
}

@Test func commandsNameTheServiceTheAgentSerialisesOn() {
    #expect(AgentCommand.perform(.stop, service: "invoices").service == "invoices")
    #expect(everyCommand[8].service == "invoices")
    #expect(AgentCommand.listServices.service == nil)
}

@Test func envelopesExpireAtTheirDeadline() {
    let envelope = CommandEnvelope(issuedAt: fixedDate, deadline: fixedDate.addingTimeInterval(60), issuedBy: "user-1", command: .listServices)
    #expect(!envelope.isExpired(at: fixedDate))
    #expect(envelope.isExpired(at: fixedDate.addingTimeInterval(61)))
    #expect(!CommandEnvelope(issuedBy: "user-1", command: .listServices).isExpired())
}

@Test func everyAgentFrameRoundTrips() throws {
    let status = ServiceStatus(service: "invoices", activeState: .active)
    let bodies: [AgentMessage.Body] = [
        .ack(CommandAck(command: "c1")),
        .ack(CommandAck(command: "c1", error: ServerCoreError(.busy, "deploying"))),
        .progress(CommandProgress(command: "c1", stage: .downloading, fractionCompleted: 0.5, message: "half")),
        .result(CommandResult(command: "c1", completedAt: fixedDate, statuses: [status])),
        .result(CommandResult(command: "c2", completedAt: fixedDate, error: ServerCoreError(.notReady, "x"), deployment: .rolledBack(from: .checkingReadiness, error: ServerCoreError(.notReady, "x")))),
        .event(.statusChanged(status)),
        .event(.logs([LogEntry(timestamp: fixedDate, priority: .info, message: "hi", service: "invoices")])),
        .event(.deployment("d1", service: "invoices", state: .succeeded)),
        .event(.resources(ServerResources(sampledAt: fixedDate, cpuUsage: 0, memoryUsedBytes: 0, memoryTotalBytes: 0, diskUsedBytes: 0, diskTotalBytes: 0, loadAverage: [], uptime: 0))),
    ]
    for (sequence, body) in bodies.enumerated() {
        let message = AgentMessage(sequence: UInt64(sequence), sentAt: fixedDate, body: body)
        #expect(try roundTrip(message) == message)
    }
    #expect(CommandAck(command: "c1").isAccepted)
    #expect(!CommandResult(command: "c1", error: ServerCoreError(.busy, "")).isSuccess)
}

@Test func everyManagerFrameRoundTrips() throws {
    let envelope = CommandEnvelope(id: "c1", issuedAt: fixedDate, issuedBy: "user-1", command: .listServices)
    for body in [ManagerMessage.Body.command(envelope), .received(through: 41)] {
        let message = ManagerMessage(sentAt: fixedDate, body: body)
        #expect(try roundTrip(message) == message)
    }
}

@Test func unknownFrameTypesAndEventKindsDecodeAsUnsupported() throws {
    let agent = try AgentProtocol.decoder.decode(
        AgentMessage.self,
        from: Data(#"{"version":1,"sequence":1,"sentAt":"2026-01-01T00:00:00Z","type":"telemetry"}"#.utf8)
    )
    #expect(agent.body == .unsupported(type: "telemetry"))

    let manager = try AgentProtocol.decoder.decode(
        ManagerMessage.self,
        from: Data(#"{"version":1,"sentAt":"2026-01-01T00:00:00.5Z","type":"enroll"}"#.utf8)
    )
    #expect(manager.body == .unsupported(type: "enroll"))

    let event = try AgentProtocol.decoder.decode(AgentEvent.self, from: Data(#"{"kind":"thermal"}"#.utf8))
    #expect(event == .unsupported(kind: "thermal"))
}
