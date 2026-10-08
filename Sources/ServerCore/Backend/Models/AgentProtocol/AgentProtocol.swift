//
//  AgentProtocol.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The protocol between a deploy agent and the Server Manager, over the WebSocket the agent opens.
///
/// The agent dials out; the Manager never connects to a host. Over that one socket the Manager
/// sends ``ManagerMessage``s — commands, and acknowledgements of events it has stored — and the
/// agent answers with ``AgentMessage``s: an ``CommandAck`` straight away, any number of
/// ``CommandProgress`` updates, exactly one ``CommandResult``, and unprompted ``AgentEvent``s.
///
/// Both ends encode and decode through ``encoder`` and ``decoder`` rather than whatever their
/// framework has configured globally, for the same reason as ``AgentControlCoding``: neither end
/// should change what the other receives by changing its own settings.
public enum AgentProtocol {

    /// The protocol version this package speaks. Bumped only for a breaking change; new message
    /// types and command kinds are additive, and an end that receives one it does not know
    /// decodes it as `unsupported` instead of failing.
    public static let version = 1

    /// The encoder for every agent-protocol frame.
    ///
    /// Dates are ISO 8601 *with* fractional seconds. Foundation's `.iso8601` strategy drops them,
    /// and log entries written in the same second would then lose their order.
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.iso8601String)
        }
        return encoder
    }()

    /// The decoder for every agent-protocol frame. Accepts ISO 8601 with or without fractional
    /// seconds.
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Date.fromISO8601String(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "\"\(string)\" is not an ISO 8601 date"
                )
            }
            return date
        }
        return decoder
    }()
}
