//
//  AgentControlTests.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Testing
import Foundation
import Vapor
import ServerFoundationCore
import ServerFoundationLogging
@testable import ServerFoundationVapor

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Configuration

@Test func doesNotStartWhenThereIsNoAgent() throws {
    // The ordinary case: someone runs the server by hand. This has to stay silent, or the
    // control channel could not be adopted without changing how the server is run today.
    #expect(try AgentControlConfiguration.resolve(from: [:]) == nil)
    #expect(try AgentControlConfiguration.resolve(from: ["FNC_CONTROL_PORT": ""]) == nil)
}

@Test func aHalfConfiguredEnvironmentFailsLoudly() {
    // Binding a listener that can stop the server, with no token on it, is not an acceptable
    // way to recover from a missing variable.
    #expect(throws: AgentControlConfigurationError.missing("FNC_CONTROL_TOKEN")) {
        try AgentControlConfiguration.resolve(from: [
            "FNC_CONTROL_PORT": "9000", "FNC_INSTANCE_ID": "abc"
        ])
    }
    #expect(throws: AgentControlConfigurationError.missing("FNC_INSTANCE_ID")) {
        try AgentControlConfiguration.resolve(from: [
            "FNC_CONTROL_PORT": "9000", "FNC_CONTROL_TOKEN": "t"
        ])
    }
    #expect(throws: AgentControlConfigurationError.invalidPort("nope")) {
        try AgentControlConfiguration.resolve(from: [
            "FNC_CONTROL_PORT": "nope", "FNC_CONTROL_TOKEN": "t", "FNC_INSTANCE_ID": "abc"
        ])
    }
    #expect(throws: AgentControlConfigurationError.invalidPort("70000")) {
        try AgentControlConfiguration.resolve(from: [
            "FNC_CONTROL_PORT": "70000", "FNC_CONTROL_TOKEN": "t", "FNC_INSTANCE_ID": "abc"
        ])
    }
}

@Test func readsWhatTheAgentInjects() throws {
    let configuration = try #require(try AgentControlConfiguration.resolve(from: [
        "FNC_INSTANCE_ID": "AB-12",
        "FNC_CONTROL_HOST": "127.0.0.1",
        "FNC_CONTROL_PORT": "51234",
        "FNC_CONTROL_TOKEN": "sekrit",
        "FNC_AGENT_URL": "http://127.0.0.1:5999"
    ]))

    #expect(configuration.instanceID == "AB-12")
    #expect(configuration.port == 51234)
    #expect(configuration.token == "sekrit")
    #expect(configuration.agentURL?.absoluteString == "http://127.0.0.1:5999")
}

@Test func defaultsToLoopbackWhenNoHostIsGiven() throws {
    let configuration = try #require(try AgentControlConfiguration.resolve(from: [
        "FNC_INSTANCE_ID": "AB-12", "FNC_CONTROL_PORT": "51234", "FNC_CONTROL_TOKEN": "t"
    ]))

    // Never 0.0.0.0. `POST /control/shutdown` must not be reachable from off-box.
    #expect(configuration.host == "127.0.0.1")
}

// MARK: - A running control channel

private struct TestProvider: AgentControlProvider {
    var state: ServerState = .online

    func serverState() async -> ServerState { state }

    func jobs() async -> [ServerJobDescriptor] {
        [ServerJobDescriptor(job: "Process", title: "Process", autoStart: true, capabilities: [.start, .stop])]
    }

    func jobStates() async -> [ServerJobStatus] {
        [ServerJobStatus(job: "Process", state: .finished(.failed("db unreachable"), on: Date(timeIntervalSince1970: 1_770_000_000)))]
    }
}

/// Binds port 0, notes what the OS handed out, and releases it.
private func freePort() throws -> Int {
    // No synchronous "give me a free port" in NIO, so bind one with a POSIX socket and let go.
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")

    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    #expect(bound == 0)

    var resolved = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &resolved) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    return Int(UInt16(bigEndian: resolved.sin_port))
}

private struct RunningControl {
    let baseURL: URL
    let token: String

    func request(_ path: String, method: String = "GET", token overrideToken: String?) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let overrideToken {
            request.setValue("Bearer \(overrideToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}

/// Starts a control channel, runs the body, and always tears both applications down.
///
/// Scoped rather than `defer { Task { … } }`: Vapor traps when an `Application` deinits without
/// `shutdown()`, and a detached teardown task races deallocation. That trap is a SIGTRAP that
/// takes the whole test process with it, so it presents as "everything failed" rather than as
/// one bad test.
private func withControl(
    provider: any AgentControlProvider = TestProvider(),
    logs: LogStorage? = nil,
    onShutdownRequest: (@Sendable () async -> Void)? = nil,
    _ body: (RunningControl) async throws -> Void
) async throws {
    let port = try freePort()
    let token = "token-\(UUID().uuidString)"

    let application = try await Application.make(.testing)
    let control = try await application.enableAgentControl(
        configuration: AgentControlConfiguration(instanceID: "test-instance", port: port, token: token),
        version: "9.9.9",
        provider: provider,
        logs: logs,
        // Without this the default handler calls exit(0) and takes the test runner with it.
        onShutdownRequest: onShutdownRequest ?? {}
    )

    let running = RunningControl(
        baseURL: URL(string: "http://127.0.0.1:\(port)/control")!,
        token: token
    )

    do {
        try await body(running)
    } catch {
        try? await control.shutdown()
        try? await application.asyncShutdown()
        throw error
    }

    try await control.shutdown()
    try await application.asyncShutdown()
}

@Test func rejectsARequestWithNoToken() async throws {
    try await withControl { running in
        let (status, _) = try await running.request("health", token: nil)
        #expect(status == 401)
    }
}

@Test func rejectsARequestWithTheWrongToken() async throws {
    try await withControl { running in
        // Loopback is not a trust boundary — any same-user process can reach this port, and one
        // of these routes stops the server.
        let (status, _) = try await running.request("health", token: "not-the-token")
        #expect(status == 401)

        // A prefix of the real token must not be treated as closer to correct.
        let (prefixStatus, _) = try await running.request("health", token: String(running.token.prefix(10)))
        #expect(prefixStatus == 401)
    }
}

@Test func healthReportsTheInstanceAndVersion() async throws {
    try await withControl { running in
        let (status, data) = try await running.request("health", token: running.token)
        #expect(status == 200)

        let health = try AgentControlServer.decoder.decode(ControlHealth.self, from: data)
        // The echoed instance id is how the agent proves this is the process it launched, and
        // not something else that has since taken the port.
        #expect(health.instanceID == "test-instance")
        #expect(health.version == "9.9.9")
        #expect(health.state == .online)
        #expect(health.uptime >= 0)
    }
}

@Test func stateCarriesTheJobResultThatTheLegacyEndpointsCannot() async throws {
    try await withControl { running in
        let (status, data) = try await running.request("state", token: running.token)
        #expect(status == 200)

        let state = try AgentControlServer.decoder.decode(ControlState.self, from: data)
        #expect(state.jobs.count == 1)
        #expect(state.jobs.first?.job == ServerJob("Process"))
        // The whole point: a failed run is distinguishable from a cancelled one here, where
        // over the legacy `WS /status/{job}` both are the string "canceled".
        #expect(state.jobs.first?.state.failureReason == "db unreachable")
    }
}

@Test func jobsAreDiscoverableAtRuntime() async throws {
    try await withControl { running in
        let (status, data) = try await running.request("jobs", token: running.token)
        #expect(status == 200)

        let jobs = try AgentControlServer.decoder.decode([ServerJobDescriptor].self, from: data)
        // This is what replaces `InvoiceJob.allCases` — the app renders controls for a server
        // it was never compiled against.
        #expect(jobs.map(\.title) == ["Process"])
        #expect(jobs.first?.supports(.start) == true)
        #expect(jobs.first?.supports(.execute) == false)
    }
}

@Test func aServerWithNoJobsAdoptsTheChannelByImplementingNothing() async throws {
    struct Bare: AgentControlProvider {
        func serverState() async -> ServerState { .online }
    }

    // This is `funico-scheduler-api-server`: no jobs, no state of its own, still manageable.
    try await withControl(provider: Bare()) { running in
        let (jobsStatus, jobsData) = try await running.request("jobs", token: running.token)
        #expect(jobsStatus == 200)
        #expect(try AgentControlServer.decoder.decode([ServerJobDescriptor].self, from: jobsData).isEmpty)

        let (healthStatus, _) = try await running.request("health", token: running.token)
        #expect(healthStatus == 200)
    }
}

@Test func shutdownIsAcceptedBeforeTheProcessGoesAway() async throws {
    let didRequestShutdown = LockedFlag()

    try await withControl(onShutdownRequest: { didRequestShutdown.set() }) { running in
        let (status, _) = try await running.request("shutdown", method: "POST", token: running.token)

        // 202 before exiting, not "connection reset". A process that vanished mid-request would
        // be indistinguishable from a crash — exactly the distinction the agent exists to make.
        #expect(status == 202)

        try await Task.sleep(for: .milliseconds(400))
        #expect(didRequestShutdown.value)
    }
}

@Test func shutdownStillRequiresTheToken() async throws {
    let didRequestShutdown = LockedFlag()

    try await withControl(onShutdownRequest: { didRequestShutdown.set() }) { running in
        let (status, _) = try await running.request("shutdown", method: "POST", token: nil)
        #expect(status == 401)

        try await Task.sleep(for: .milliseconds(300))
        #expect(didRequestShutdown.value == false)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock(); flag = true; lock.unlock()
    }
}
