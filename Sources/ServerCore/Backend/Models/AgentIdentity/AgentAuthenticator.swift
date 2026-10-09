//
//  AgentAuthenticator.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The Manager's side of the per-connection handshake: issues an ``AgentChallenge`` and verifies
/// the ``AgentChallengeResponse``.
///
/// ```swift
/// let authenticator = AgentAuthenticator(
///     manager: "manager.funico.internal",
///     verifier: verifier,
///     nonces: InMemoryAgentNonceStore()
/// )
///
/// // On hello: issue, keep it with the connection, send it.
/// let challenge = authenticator.challenge(for: hello.agent)
///
/// // On response: verify against the challenge *kept*, never one the agent echoes back.
/// try await authenticator.verify(response, to: challenge, from: enrolledAgent)
/// ```
///
/// ``verify(_:to:from:now:)`` checks, in order:
///
/// 1. the response answers this challenge (its nonce);
/// 2. the response, the challenge and the enrolled record name the same agent;
/// 3. the challenge's audience is this Manager;
/// 4. now is within `issuedAt ..< expiresAt`;
/// 5. the nonce has not been consumed before — and consumes it;
/// 6. the signature verifies against the enrolled key.
///
/// The nonce is consumed *before* the signature is checked, so each challenge gets exactly one
/// attempt: a failed response cannot be followed by another guess at the same challenge. An agent
/// that fails reconnects and is challenged afresh.
///
/// No clock-skew allowance is applied, and none is needed: the Manager issues the challenge and
/// judges its expiry by the same clock. The agent's clock is never consulted — see
/// ``AgentChallenge/response(as:for:signer:)``.
public struct AgentAuthenticator: Sendable {

    /// How long an agent has to answer a challenge by default: thirty seconds.
    ///
    /// An agent answers in milliseconds — one signature over a few hundred bytes. The rest is
    /// headroom for a loaded host, a slow link across the tailnet, or a process paused by the
    /// scheduler. Longer buys nothing: each challenge is single use and bound to one connection, so
    /// the lifetime only bounds how long the Manager must remember the nonce.
    public static let defaultChallengeLifetime: TimeInterval = 30

    /// This Manager's identity; challenges carry it as their audience.
    public var manager: ManagerID

    /// Checks response signatures.
    public var verifier: any AgentSignatureVerifier

    /// Records answered challenges, so each is accepted at most once.
    public var nonces: any AgentNonceStore

    /// How long a challenge from ``challenge(for:now:)`` stays answerable.
    public var challengeLifetime: TimeInterval

    /// Creates an authenticator.
    ///
    /// - Parameters:
    ///   - manager: this Manager's identity.
    ///   - verifier: checks signatures.
    ///   - nonces: records answered challenges; must be shared by every instance serving the same
    ///     agents.
    ///   - challengeLifetime: how long a challenge stays answerable; ``defaultChallengeLifetime``
    ///     by default.
    public init(
        manager: ManagerID,
        verifier: any AgentSignatureVerifier,
        nonces: any AgentNonceStore,
        challengeLifetime: TimeInterval = AgentAuthenticator.defaultChallengeLifetime
    ) {
        self.manager = manager
        self.verifier = verifier
        self.nonces = nonces
        self.challengeLifetime = challengeLifetime
    }

    /// A fresh challenge for the agent a connection claims to be.
    ///
    /// Keep it with the connection; ``verify(_:to:from:now:)`` needs the challenge as issued.
    ///
    /// - Parameters:
    ///   - agent: the identity from the agent's ``AgentHello``.
    ///   - now: the current time.
    /// - Returns: the challenge to send.
    public func challenge(for agent: AgentID, now: Date = Date()) -> AgentChallenge {
        let issuedAt = now.truncatedToSeconds
        return AgentChallenge(
            nonce: .random(),
            agent: agent,
            audience: manager,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(challengeLifetime)
        )
    }

    /// Verifies a response to a challenge this Manager issued. Returns normally only if the
    /// connection is authenticated as `enrolled.agent`.
    ///
    /// - Parameters:
    ///   - response: what the agent sent.
    ///   - challenge: the challenge issued on this connection, as kept by the Manager.
    ///   - enrolled: the stored record for the agent the connection claims to be.
    ///   - now: the current time.
    /// - Throws: an ``AgentAuthenticationError`` naming the first check that failed — log it, and
    ///   send the peer its ``AgentAuthenticationError/serverCoreError`` — or whatever the nonce
    ///   store throws.
    public func verify(
        _ response: AgentChallengeResponse,
        to challenge: AgentChallenge,
        from enrolled: EnrolledAgent,
        now: Date = Date()
    ) async throws {
        guard response.nonce == challenge.nonce else { throw AgentAuthenticationError.challengeMismatch }
        guard response.agent == challenge.agent, enrolled.agent == challenge.agent else {
            throw AgentAuthenticationError.wrongAgent
        }
        guard challenge.audience == manager else { throw AgentAuthenticationError.wrongAudience }
        guard challenge.issuedAt <= now, now < challenge.expiresAt else {
            throw AgentAuthenticationError.expired
        }
        guard try await nonces.consume(challenge.nonce, expiresAt: challenge.expiresAt, now: now) else {
            throw AgentAuthenticationError.replayed
        }
        guard verifier.isValidSignature(response.signature, of: challenge.signingBytes, by: enrolled.publicKey) else {
            throw AgentAuthenticationError.invalidSignature
        }
    }
}
