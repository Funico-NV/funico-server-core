//
//  Application+AgentControl.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

#if Vapor
import Foundation
import Vapor
import ServerCore
import ServerCoreLogging

extension Application {

    /// Opens the agent control channel, if this process is running under an agent.
    ///
    /// One line in a managed server's `main`:
    ///
    /// ```swift
    /// try await app.enableAgentControl(version: "1.4.16")
    /// ```
    ///
    /// A server started by hand has no `FNC_CONTROL_PORT`, so this returns `nil` and changes
    /// nothing. That is what lets the control channel be adopted without changing how anyone runs
    /// the server today.
    ///
    /// - Parameters:
    ///   - version: reported on `/control/health`, so the agent can tell whether a deploy actually
    ///     took effect.
    ///   - provider: what the server says about itself. Defaults to
    ///     ``StatelessAgentControlProvider``, which is right for a server with no job concept.
    ///   - logs: when supplied, `WS /control/events` streams structured `FNCLog` records. Without
    ///     it the agent is stuck parsing stdout.
    ///   - onShutdownRequest: what `POST /control/shutdown` should do. The default stops the main
    ///     HTTP server and exits 0. Supply your own to drain work first.
    /// - Returns: `nil` when not running under an agent.
    @discardableResult
    public func enableAgentControl(
        version: String,
        provider: any AgentControlProvider = StatelessAgentControlProvider(),
        logs: LogStorage? = nil,
        onShutdownRequest: (@Sendable () async -> Void)? = nil
    ) async throws -> AgentControlServer? {
        guard let configuration = try AgentControlConfiguration.resolve() else {
            logger.debug("No \(AgentControlConfiguration.portKey); agent control channel not started")
            return nil
        }

        return try await enableAgentControl(
            configuration: configuration,
            version: version,
            provider: provider,
            logs: logs,
            onShutdownRequest: onShutdownRequest
        )
    }

    /// Opens the control channel against an explicit configuration, bypassing the environment.
    ///
    /// Exists so the channel is testable: `resolve()` reads the process environment, which a test
    /// cannot vary per case, and the default shutdown handler calls `exit(0)`, which would take the
    /// test runner with it.
    @discardableResult
    public func enableAgentControl(
        configuration: AgentControlConfiguration,
        version: String,
        provider: any AgentControlProvider = StatelessAgentControlProvider(),
        logs: LogStorage? = nil,
        onShutdownRequest: (@Sendable () async -> Void)? = nil
    ) async throws -> AgentControlServer {
        let control = try await Application.make(environment, .shared(eventLoopGroup))
        control.logger = logger

        // Loopback only. The main listener is 0.0.0.0; this one must not be.
        control.http.server.configuration.hostname = configuration.host
        control.http.server.configuration.port = configuration.port

        let server = AgentControlServer(configuration: configuration, application: control)
        let startedAt = Date()

        let shutdown = onShutdownRequest ?? { [weak self] in
            // Stop accepting, then leave. `exit(0)` is what the agent reads as a clean stop, as
            // opposed to a crash — and it is the same code path on every platform, which is the
            // entire reason the primary stop path is not a signal.
            await self?.server.shutdown()
            exit(0)
        }

        try Self.registerControlRoutes(
            on: control,
            configuration: configuration,
            provider: provider,
            logs: logs,
            version: version,
            startedAt: startedAt,
            sequencing: server,
            onShutdownRequest: shutdown
        )

        // `start(address:)` rather than `execute()`: this listener is embedded alongside the real
        // server, so it must return rather than take over the process.
        try await control.server.start(address: .hostname(configuration.host, port: configuration.port))

        logger.info("Agent control channel on \(configuration.host):\(configuration.port)", metadata: [
            "instance": .string(configuration.instanceID)
        ])

        return server
    }

    private static func registerControlRoutes(
        on control: Application,
        configuration: AgentControlConfiguration,
        provider: any AgentControlProvider,
        logs: LogStorage?,
        version: String,
        startedAt: Date,
        sequencing server: AgentControlServer,
        onShutdownRequest: @escaping @Sendable () async -> Void
    ) throws {
        let instanceID = configuration.instanceID
        let routes = control
            .grouped(ControlTokenMiddleware(token: configuration.token))
            .grouped("control")

        routes.get("health") { _ async throws -> Response in
            try Self.json(ControlHealth(
                instanceID: instanceID,
                uptime: Date().timeIntervalSince(startedAt),
                version: version,
                state: await provider.serverState()
            ))
        }

        routes.get("state") { _ async throws -> Response in
            try Self.json(ControlState(
                instanceID: instanceID,
                state: await provider.serverState(),
                jobs: await provider.jobStates()
            ))
        }

        routes.get("jobs") { _ async throws -> Response in
            try Self.json(await provider.jobs())
        }

        routes.post("shutdown") { _ async -> Response in
            // Answer first. The agent needs to know the request was accepted; if the process
            // vanished before responding, a stop would be indistinguishable from a crash.
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await onShutdownRequest()
            }
            return Response(status: .accepted)
        }

        routes.webSocket("events") { request, websocket async in
            await Self.streamEvents(
                to: websocket,
                request: request,
                serverID: instanceID,
                provider: provider,
                logs: logs,
                sequencing: server
            )
        }
    }

    /// Encodes with the control channel's own encoder rather than the process-wide one.
    private static func json(_ value: some Encodable) throws -> Response {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")

        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: try AgentControlServer.encoder.encode(value))
        )
    }

    private static func streamEvents(
        to websocket: WebSocket,
        request: Request,
        serverID: String,
        provider: any AgentControlProvider,
        logs: LogStorage?,
        sequencing server: AgentControlServer
    ) async {
        @Sendable func send(_ payload: ServerEventEnvelope.Payload) async {
            let envelope = ServerEventEnvelope(
                sequence: server.nextSequence(),
                serverID: serverID,
                payload: payload
            )
            guard let data = try? AgentControlServer.encoder.encode(envelope) else { return }
            try? await websocket.send(String(decoding: data, as: UTF8.self))
        }

        let logStream = Task {
            guard let logs else { return }
            for await log in logs.stream() {
                await send(.log(log))
            }
        }

        // State is polled rather than pushed because ``AgentControlProvider`` is a pull interface
        // — a server should not have to adopt an observation library to be manageable. Emitting
        // only on change keeps the stream quiet.
        let stateStream = Task {
            var last: ServerState?
            while !Task.isCancelled {
                let current = await provider.serverState()
                if current != last {
                    last = current
                    await send(.state(current))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        try? await websocket.onClose.get()
        logStream.cancel()
        stateStream.cancel()
    }
}
#endif
