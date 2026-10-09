//
//  AgentAuthenticationError.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Why an enrollment or a challenge response was refused.
///
/// Specific, for the Manager's log and for tests. A peer is told only
/// ``ServerCoreError/Code/authenticationFailed`` — see ``serverCoreError`` — because naming the check
/// that failed helps someone probing far more than it helps a legitimate agent, whose operator reads
/// the Manager's log anyway.
public enum AgentAuthenticationError: Error, Sendable, Hashable {

    /// The response answers a different challenge than the one issued on this connection.
    case challengeMismatch

    /// The challenge, the response or the enrolled record names a different agent. Also thrown by
    /// the agent itself, before signing, for a challenge addressed to someone else.
    case wrongAgent

    /// The challenge was issued for a different Manager. Also thrown by the agent, before signing,
    /// for a challenge from a Manager it did not enroll with.
    case wrongAudience

    /// The challenge is outside its validity window by the Manager's clock.
    case expired

    /// The challenge has already been answered once. Replays end here, whatever their signature.
    case replayed

    /// The signature does not verify against the enrolled key: a different key, altered bytes, or
    /// an algorithm the verifier does not implement.
    case invalidSignature

    /// The enrollment token was never issued or has already been used. The two are not
    /// distinguished, so a guesser cannot tell a spent token from a wrong one.
    case unknownEnrollmentToken

    /// The enrollment token was issued but has expired. It has been consumed all the same.
    case enrollmentTokenExpired

    /// The enrollment request's proof-of-possession signature does not verify against the key it
    /// presents.
    case invalidProof

    /// What to send the peer: always ``ServerCoreError/Code/authenticationFailed`` with a generic
    /// message.
    public var serverCoreError: ServerCoreError {
        ServerCoreError(.authenticationFailed, "agent authentication failed")
    }
}
