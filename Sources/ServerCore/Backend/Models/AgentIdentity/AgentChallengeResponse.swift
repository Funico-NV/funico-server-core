//
//  AgentChallengeResponse.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The agent's answer to an ``AgentChallenge``: which challenge, who answers, and the signature.
///
/// ```json
/// { "nonce": "…", "agent": "6f1c…", "signature": "…" }
/// ```
///
/// Deliberately does not echo the rest of the challenge. The Manager verifies the signature against
/// the challenge *it issued and kept*, never against fields the peer sent back, so there is nothing
/// for a peer to alter.
public struct AgentChallengeResponse: Sendable, Hashable, Codable {

    /// The nonce of the challenge being answered.
    public var nonce: AgentChallengeNonce

    /// The agent answering.
    public var agent: AgentID

    /// A signature over the challenge's ``AgentChallenge/signingBytes``.
    public var signature: AgentSignature

    /// Creates a response. An agent normally uses
    /// ``AgentChallenge/response(as:for:signer:)``, which checks the challenge first.
    ///
    /// - Parameters:
    ///   - nonce: the challenge's nonce.
    ///   - agent: the agent answering.
    ///   - signature: the signature over the challenge.
    public init(nonce: AgentChallengeNonce, agent: AgentID, signature: AgentSignature) {
        self.nonce = nonce
        self.agent = agent
        self.signature = signature
    }
}
