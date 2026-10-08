//
//  AgentMessage.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One frame from an agent to the Manager.
///
/// ```json
/// { "version": 1, "sequence": 42, "sentAt": "…", "type": "ack", "ack": { "command": "…" } }
/// ```
///
/// ``sequence`` is what makes a reconnect lossless. The agent numbers every frame, keeps the ones
/// the Manager has not yet confirmed with ``ManagerMessage/Body/received(through:)``, and replays
/// them after reconnecting. The Manager drops any sequence it has already stored, so a replay is
/// harmless.
public struct AgentMessage: Sendable, Hashable, Codable {

    /// The protocol version the frame was written in; ``AgentProtocol/version`` by default.
    public var version: Int

    /// Monotonically increasing per agent, across reconnects.
    public var sequence: UInt64

    /// When the agent sent it the first time. A replayed frame keeps its original time.
    public var sentAt: Date

    /// What the frame carries.
    public var body: Body

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - version: the protocol version.
    ///   - sequence: the frame's number.
    ///   - sentAt: when it was first sent.
    ///   - body: what it carries.
    public init(
        version: Int = AgentProtocol.version,
        sequence: UInt64,
        sentAt: Date = Date(),
        body: Body
    ) {
        self.version = version
        self.sequence = sequence
        self.sentAt = sentAt
        self.body = body
    }

    /// What an agent frame carries.
    public enum Body: Sendable, Hashable {

        /// A command was accepted or refused.
        case ack(CommandAck)

        /// A long-running command moved on.
        case progress(CommandProgress)

        /// A command ended.
        case result(CommandResult)

        /// Something happened on the host.
        case event(AgentEvent)

        /// A type this version does not know. Never sent; only decoded, and then ignored.
        case unsupported(type: String)
    }

    private enum CodingKeys: String, CodingKey {
        case version, sequence, sentAt, type, ack, progress, result, event
    }

    /// Decodes a frame. An unknown `type` becomes ``Body/unsupported(type:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        sentAt = try container.decode(Date.self, forKey: .sentAt)

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ack": body = .ack(try container.decode(CommandAck.self, forKey: .ack))
        case "progress": body = .progress(try container.decode(CommandProgress.self, forKey: .progress))
        case "result": body = .result(try container.decode(CommandResult.self, forKey: .result))
        case "event": body = .event(try container.decode(AgentEvent.self, forKey: .event))
        default: body = .unsupported(type: type)
        }
    }

    /// Encodes a frame.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(sentAt, forKey: .sentAt)

        switch body {
        case .ack(let ack):
            try container.encode("ack", forKey: .type)
            try container.encode(ack, forKey: .ack)
        case .progress(let progress):
            try container.encode("progress", forKey: .type)
            try container.encode(progress, forKey: .progress)
        case .result(let result):
            try container.encode("result", forKey: .type)
            try container.encode(result, forKey: .result)
        case .event(let event):
            try container.encode("event", forKey: .type)
            try container.encode(event, forKey: .event)
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
