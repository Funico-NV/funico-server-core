//
//  AgentHandshakeMessage.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One frame of the handshake that opens every agent connection, in either direction.
///
/// ```
/// agent   → hello      { agent }
/// Manager → challenge  { nonce, agent, audience, issuedAt, expiresAt }
/// agent   → response   { nonce, agent, signature }
/// Manager → accepted                       or   rejected { code, message }
/// ```
///
/// ```json
/// { "version": 1, "type": "hello", "hello": { "agent": "6f1c…" } }
/// ```
///
/// Separate from ``AgentMessage`` and ``ManagerMessage`` on purpose. Those are sequenced and
/// replayed after a reconnect; a handshake frame must never be. Until the Manager has sent
/// ``Body/accepted``, neither end sends or acts on anything but a handshake frame — the Manager in
/// particular processes no ``AgentMessage`` from an unauthenticated connection.
///
/// Encoded with ``AgentProtocol/encoder`` like every other agent-protocol frame. An unknown `type`
/// decodes as ``Body/unsupported(type:)`` rather than failing, so the handshake can grow — a
/// capability exchange, say — without breaking an older peer.
public struct AgentHandshakeMessage: Sendable, Hashable, Codable {

    /// The protocol version the frame was written in; ``AgentProtocol/version`` by default.
    public var version: Int

    /// What the frame carries.
    public var body: Body

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - version: the protocol version.
    ///   - body: what it carries.
    public init(version: Int = AgentProtocol.version, body: Body) {
        self.version = version
        self.body = body
    }

    /// What a handshake frame carries.
    public enum Body: Sendable, Hashable {

        /// Agent → Manager: the identity the connection claims. Nothing is trusted until the
        /// challenge for it is answered.
        case hello(AgentHello)

        /// Manager → agent: prove it.
        case challenge(AgentChallenge)

        /// Agent → Manager: the signed answer.
        case response(AgentChallengeResponse)

        /// Manager → agent: authenticated. ``AgentMessage`` and ``ManagerMessage`` frames follow.
        case accepted

        /// Manager → agent: refused, with ``ServerCoreError/Code/authenticationFailed``. The
        /// Manager then closes the connection.
        case rejected(ServerCoreError)

        /// A type this version does not know. Never sent; only decoded, and then ignored.
        case unsupported(type: String)
    }

    private enum CodingKeys: String, CodingKey {
        case version, type, hello, challenge, response, error
    }

    /// Decodes a frame. An unknown `type` becomes ``Body/unsupported(type:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "hello": body = .hello(try container.decode(AgentHello.self, forKey: .hello))
        case "challenge": body = .challenge(try container.decode(AgentChallenge.self, forKey: .challenge))
        case "response": body = .response(try container.decode(AgentChallengeResponse.self, forKey: .response))
        case "accepted": body = .accepted
        case "rejected": body = .rejected(try container.decode(ServerCoreError.self, forKey: .error))
        default: body = .unsupported(type: type)
        }
    }

    /// Encodes a frame.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)

        switch body {
        case .hello(let hello):
            try container.encode("hello", forKey: .type)
            try container.encode(hello, forKey: .hello)
        case .challenge(let challenge):
            try container.encode("challenge", forKey: .type)
            try container.encode(challenge, forKey: .challenge)
        case .response(let response):
            try container.encode("response", forKey: .type)
            try container.encode(response, forKey: .response)
        case .accepted:
            try container.encode("accepted", forKey: .type)
        case .rejected(let error):
            try container.encode("rejected", forKey: .type)
            try container.encode(error, forKey: .error)
        case .unsupported(let type):
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "\"\(type)\" is a received frame type this version does not know; it cannot be sent"
                )
            )
        }
    }
}

/// The first frame an agent sends: who it claims to be, so the Manager can challenge that identity.
public struct AgentHello: Sendable, Hashable, Codable {

    /// The identity from the agent's ``AgentEnrollmentResponse``.
    public var agent: AgentID

    /// Creates a hello.
    ///
    /// - Parameter agent: the agent's identity.
    public init(agent: AgentID) {
        self.agent = agent
    }
}
