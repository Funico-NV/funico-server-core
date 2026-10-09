//
//  AgentEnrollmentToken.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The one-time secret an operator carries from the Manager to a host to enroll its agent.
///
/// The Manager issues it with ``AgentEnrollmentAuthority/issueToken(for:now:)``; the operator runs
/// `funico-server-agent enroll --token …` on the host; the agent presents it once, in an
/// ``AgentEnrollmentRequest``, and it is gone. It is the only secret in the protocol that ever
/// crosses a network, which is why it is single use and short-lived.
///
/// Encoded as a bare string. Opaque to everyone but the Manager that issued it: only its value is
/// compared, never parsed.
///
/// ``description`` is redacted, so interpolating a token into a log line does not leak it. Use
/// ``rawValue`` deliberately, once, to show it to the operator.
public struct AgentEnrollmentToken:
    Sendable, Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{

    /// The prefix ``generate()`` puts on every token.
    ///
    /// A recognisable prefix is what lets secret scanners and the agent's log redaction (which
    /// strips known secret patterns before forwarding) find a token that was pasted somewhere it
    /// should not have been.
    public static let prefix = "fnc-enroll-"

    /// The token itself. Show it to the operator once; never log it.
    public let rawValue: String

    /// Wraps a token received from an operator or decoded from a request.
    ///
    /// - Parameter rawValue: the token as issued.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// A fresh token: ``prefix`` followed by 32 random bytes in unpadded base64url.
    public static func generate() -> AgentEnrollmentToken {
        AgentEnrollmentToken(rawValue: prefix + Base64URL.encode(Base64URL.randomBytes(32)))
    }

    /// Always `AgentEnrollmentToken(redacted)`.
    public var description: String { "AgentEnrollmentToken(redacted)" }

    /// Always `AgentEnrollmentToken(redacted)`, so `String(reflecting:)` does not leak it either.
    public var debugDescription: String { description }

    /// A mirror with no children, so `dump(_:)` does not leak it either.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Decodes a bare string.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// Encodes as a bare string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
