//
//  ManagerMessage.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One frame from the Manager to an agent.
///
/// ```json
/// { "version": 1, "sentAt": "…", "type": "command", "command": { "id": "…", "command": { "kind": "listServices" } } }
/// ```
///
/// Unnumbered, unlike ``AgentMessage``: commands carry their own ``CommandID`` and are idempotent,
/// so the Manager makes a lost one good by re-sending it.
public struct ManagerMessage: Sendable, Hashable, Codable {

    /// The protocol version the frame was written in; ``AgentProtocol/version`` by default.
    public var version: Int

    /// When the Manager sent it.
    public var sentAt: Date

    /// What the frame carries.
    public var body: Body

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - version: the protocol version.
    ///   - sentAt: when it was sent.
    ///   - body: what it carries.
    public init(version: Int = AgentProtocol.version, sentAt: Date = Date(), body: Body) {
        self.version = version
        self.sentAt = sentAt
        self.body = body
    }

    /// What a Manager frame carries.
    public enum Body: Sendable, Hashable {

        /// Run a command.
        case command(CommandEnvelope)

        /// The Manager has durably stored every ``AgentMessage`` up to and including this sequence
        /// number. The agent may forget them; it replays only later ones after a reconnect.
        case received(through: UInt64)

        /// A type this version does not know. Never sent; only decoded, and then ignored.
        case unsupported(type: String)
    }

    private enum CodingKeys: String, CodingKey {
        case version, sentAt, type, command, through
    }

    /// Decodes a frame. An unknown `type` becomes ``Body/unsupported(type:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sentAt = try container.decode(Date.self, forKey: .sentAt)

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "command": body = .command(try container.decode(CommandEnvelope.self, forKey: .command))
        case "received": body = .received(through: try container.decode(UInt64.self, forKey: .through))
        default: body = .unsupported(type: type)
        }
    }

    /// Encodes a frame.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(sentAt, forKey: .sentAt)

        switch body {
        case .command(let envelope):
            try container.encode("command", forKey: .type)
            try container.encode(envelope, forKey: .command)
        case .received(let sequence):
            try container.encode("received", forKey: .type)
            try container.encode(sequence, forKey: .through)
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
