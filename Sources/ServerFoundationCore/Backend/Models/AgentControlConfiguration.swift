//
//  AgentControlConfiguration.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// How a managed server learns that it is running under the agent.
///
/// The agent picks a free port and a fresh 32-byte token at launch and injects both into the
/// child's environment. A server started by hand sees none of this and simply does not open a
/// control listener.
public struct AgentControlConfiguration: Sendable, Hashable {

    public static let instanceIDKey = "FNC_INSTANCE_ID"
    public static let hostKey = "FNC_CONTROL_HOST"
    public static let portKey = "FNC_CONTROL_PORT"
    public static let tokenKey = "FNC_CONTROL_TOKEN"
    public static let agentURLKey = "FNC_AGENT_URL"

    /// Loopback. Deliberately not configurable to `0.0.0.0` — see `AgentControlServer`.
    public static let defaultHost = "127.0.0.1"

    public let instanceID: String
    public let host: String
    public let port: Int
    public let token: String
    public let agentURL: URL?

    public init(instanceID: String, host: String = defaultHost, port: Int, token: String, agentURL: URL? = nil) {
        self.instanceID = instanceID
        self.host = host
        self.port = port
        self.token = token
        self.agentURL = agentURL
    }

    /// Reads the configuration the agent injected.
    ///
    /// - Returns: `nil` when `FNC_CONTROL_PORT` is absent, which is the ordinary "not running
    ///   under an agent" case and must stay silent.
    /// - Throws: when the port *is* present but the rest is not. A half-configured environment
    ///   must fail loudly: the alternative is binding a control listener that can stop the
    ///   server, with no token on it.
    public static func resolve(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AgentControlConfiguration? {
        guard let rawPort = environment[portKey], !rawPort.isEmpty else { return nil }

        guard let port = Int(rawPort), (1...65535).contains(port) else {
            throw AgentControlConfigurationError.invalidPort(rawPort)
        }
        guard let token = environment[tokenKey], !token.isEmpty else {
            throw AgentControlConfigurationError.missing(tokenKey)
        }
        guard let instanceID = environment[instanceIDKey], !instanceID.isEmpty else {
            throw AgentControlConfigurationError.missing(instanceIDKey)
        }

        return AgentControlConfiguration(
            instanceID: instanceID,
            host: environment[hostKey].flatMap { $0.isEmpty ? nil : $0 } ?? defaultHost,
            port: port,
            token: token,
            agentURL: environment[agentURLKey].flatMap(URL.init(string:))
        )
    }
}

public enum AgentControlConfigurationError: Error, Sendable, Hashable {

    case missing(String)
    case invalidPort(String)
}

extension AgentControlConfigurationError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .missing(let key):
            "\(AgentControlConfiguration.portKey) is set, so this process is under the agent, but \(key) is missing"
        case .invalidPort(let value):
            "\(AgentControlConfiguration.portKey) is not a valid port: '\(value)'"
        }
    }
}
