//
//  AgentChallenge.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// What the Manager sends an agent on every connection, and the agent must sign to prove it holds
/// its enrolled key.
///
/// ```json
/// { "nonce": "…", "agent": "6f1c…", "audience": "manager.funico.internal",
///   "issuedAt": 1770000000, "expiresAt": 1770000030 }
/// ```
///
/// Every field is in the signed bytes (``signingBytes``), and each is there to close one hole: the
/// nonce makes a signature useless on any other connection, the agent ID stops one agent answering
/// for another, the audience stops a signature made for one Manager being presented to another,
/// and the expiry bounds how long an unanswered challenge stays answerable.
///
/// Times are whole seconds — the initializer truncates them — and travel as integer Unix seconds
/// rather than ISO 8601 strings, so both ends derive identical signed bytes. See
/// ``AgentSigningPayload``.
public struct AgentChallenge: Sendable, Hashable, Codable {

    /// Unique to this challenge.
    public var nonce: AgentChallengeNonce

    /// The agent the connection claims to be.
    public var agent: AgentID

    /// The Manager that issued it.
    public var audience: ManagerID

    /// When the Manager issued it, in whole seconds.
    public var issuedAt: Date

    /// When it stops being answerable, in whole seconds.
    public var expiresAt: Date

    /// Creates a challenge. Fractions of a second are dropped from both dates.
    ///
    /// The Manager normally creates one with ``AgentAuthenticator/challenge(for:now:)``.
    ///
    /// - Parameters:
    ///   - nonce: the random value; ``AgentChallengeNonce/random()`` unless testing.
    ///   - agent: the agent the connection claims to be.
    ///   - audience: the issuing Manager.
    ///   - issuedAt: when it was issued.
    ///   - expiresAt: when it stops being answerable.
    public init(
        nonce: AgentChallengeNonce = .random(),
        agent: AgentID,
        audience: ManagerID,
        issuedAt: Date,
        expiresAt: Date
    ) {
        self.nonce = nonce
        self.agent = agent
        self.audience = audience
        self.issuedAt = issuedAt.truncatedToSeconds
        self.expiresAt = expiresAt.truncatedToSeconds
    }

    /// The bytes a response signs:
    /// `field(challengeContext) ‖ field(nonce) ‖ field(audience) ‖ field(agent) ‖ field(issuedAt) ‖ field(expiresAt)`,
    /// in the layout ``AgentSigningPayload`` describes.
    public var signingBytes: [UInt8] {
        var writer = CanonicalWriter(context: AgentSigningPayload.challengeContext)
        writer.append(nonce.rawRepresentation)
        writer.append(audience.rawValue)
        writer.append(agent.rawValue)
        writer.append(issuedAt.unixSeconds)
        writer.append(expiresAt.unixSeconds)
        return writer.bytes
    }

    /// Signs this challenge, as the agent, after checking it is addressed to this agent by the
    /// Manager it enrolled with.
    ///
    /// The agent does **not** check the expiry. Its clock and the Manager's may disagree by
    /// minutes, and the Manager — which issued the challenge and verifies it with the same clock —
    /// is the only party that can judge it. Refusing here would make a skewed host clock lock the
    /// agent out with no Manager-side log of why.
    ///
    /// - Parameters:
    ///   - agent: the agent's own identity, from its ``AgentEnrollmentResponse``.
    ///   - manager: the Manager it enrolled with, from the same response.
    ///   - signer: the agent's key.
    /// - Returns: the response to send.
    /// - Throws: ``AgentAuthenticationError/wrongAgent`` or
    ///   ``AgentAuthenticationError/wrongAudience`` without signing anything, or whatever the
    ///   signer throws.
    public func response(
        as agent: AgentID,
        for manager: ManagerID,
        signer: any AgentSigner
    ) async throws -> AgentChallengeResponse {
        guard self.agent == agent else { throw AgentAuthenticationError.wrongAgent }
        guard audience == manager else { throw AgentAuthenticationError.wrongAudience }

        return AgentChallengeResponse(
            nonce: nonce,
            agent: agent,
            signature: try await signer.sign(signingBytes)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case nonce, agent, audience, issuedAt, expiresAt
    }

    /// Decodes a challenge; `issuedAt` and `expiresAt` are integer Unix seconds.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            nonce: try container.decode(AgentChallengeNonce.self, forKey: .nonce),
            agent: try container.decode(AgentID.self, forKey: .agent),
            audience: try container.decode(ManagerID.self, forKey: .audience),
            issuedAt: Date(timeIntervalSince1970: TimeInterval(try container.decode(Int64.self, forKey: .issuedAt))),
            expiresAt: Date(timeIntervalSince1970: TimeInterval(try container.decode(Int64.self, forKey: .expiresAt)))
        )
    }

    /// Encodes a challenge with integer Unix seconds, whatever the encoder's date strategy.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(agent, forKey: .agent)
        try container.encode(audience, forKey: .audience)
        try container.encode(issuedAt.unixSeconds, forKey: .issuedAt)
        try container.encode(expiresAt.unixSeconds, forKey: .expiresAt)
    }
}
