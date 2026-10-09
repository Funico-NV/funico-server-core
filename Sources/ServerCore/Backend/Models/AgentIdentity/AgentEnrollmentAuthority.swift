//
//  AgentEnrollmentAuthority.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The Manager's side of enrollment: issues one-time tokens, and turns a valid
/// ``AgentEnrollmentRequest`` into an ``EnrolledAgent``.
///
/// ```swift
/// let authority = AgentEnrollmentAuthority(
///     manager: "manager.funico.internal",
///     tokens: tokenStore,
///     verifier: verifier
/// )
///
/// // An administrator adds a server; show them grant.token.rawValue once.
/// let grant = try await authority.issueToken(for: "box-1")
///
/// // Later, the agent on that host posts its request.
/// let enrolled = try await authority.enroll(request)      // persist this
/// let reply = authority.response(for: enrolled)           // send this
/// ```
///
/// The checks, in order: the proof of possession verifies against the presented key; the token is
/// redeemed (removed) from the store; it had not expired. The proof comes first so that a garbled
/// request does not burn the operator's token. Redemption comes before the expiry check so that an
/// expired token is consumed too, and cannot be retried.
public struct AgentEnrollmentAuthority: Sendable {

    /// How long an enrollment token stays valid by default: fifteen minutes.
    ///
    /// Long enough for an administrator to create the server in the Manager, open a shell on the
    /// host and paste the command. Short enough that a token left in a shell history, a ticket or a
    /// chat message is dead by the time anyone finds it.
    public static let defaultTokenLifetime: TimeInterval = 15 * 60

    /// This Manager's identity, returned to every enrolled agent as the audience it must expect.
    public var manager: ManagerID

    /// Where issued tokens wait to be redeemed.
    public var tokens: any AgentEnrollmentTokenStore

    /// Checks proofs of possession.
    public var verifier: any AgentSignatureVerifier

    /// How long a token issued by ``issueToken(for:now:)`` stays valid.
    public var tokenLifetime: TimeInterval

    /// Mints the identity for a newly enrolled agent. A random UUID by default: an agent ID is a
    /// name, not a secret, but it must never repeat — re-enrolling a host creates a new identity.
    public var makeAgentID: @Sendable () -> AgentID

    /// Creates an authority.
    ///
    /// - Parameters:
    ///   - manager: this Manager's identity.
    ///   - tokens: where issued tokens are kept.
    ///   - verifier: checks enrollment proofs.
    ///   - tokenLifetime: how long a token stays valid; ``defaultTokenLifetime`` by default.
    ///   - makeAgentID: mints new agent identities; a lowercase UUID by default.
    public init(
        manager: ManagerID,
        tokens: any AgentEnrollmentTokenStore,
        verifier: any AgentSignatureVerifier,
        tokenLifetime: TimeInterval = AgentEnrollmentAuthority.defaultTokenLifetime,
        makeAgentID: @escaping @Sendable () -> AgentID = { AgentID(UUID().uuidString.lowercased()) }
    ) {
        self.manager = manager
        self.tokens = tokens
        self.verifier = verifier
        self.tokenLifetime = tokenLifetime
        self.makeAgentID = makeAgentID
    }

    /// Issues a token that enrolls one agent for `server`, and stores it.
    ///
    /// - Parameters:
    ///   - server: the server the agent will speak for.
    ///   - now: the current time.
    /// - Returns: the grant; show ``AgentEnrollmentGrant/token`` to the administrator once.
    public func issueToken(for server: ServerID, now: Date = Date()) async throws -> AgentEnrollmentGrant {
        let grant = AgentEnrollmentGrant(
            token: .generate(),
            server: server,
            expiresAt: now.addingTimeInterval(tokenLifetime)
        )
        try await tokens.save(grant)
        return grant
    }

    /// Enrolls the agent that sent `request`, consuming its token.
    ///
    /// - Parameters:
    ///   - request: what the agent sent.
    ///   - now: the current time.
    /// - Returns: the record to persist; its key is what every later connection verifies against.
    /// - Throws: ``AgentAuthenticationError/invalidProof``,
    ///   ``AgentAuthenticationError/unknownEnrollmentToken`` or
    ///   ``AgentAuthenticationError/enrollmentTokenExpired``; or whatever the store throws.
    public func enroll(_ request: AgentEnrollmentRequest, now: Date = Date()) async throws -> EnrolledAgent {
        let proven = verifier.isValidSignature(
            request.proof,
            of: AgentEnrollmentRequest.signingBytes(token: request.token, publicKey: request.publicKey),
            by: request.publicKey
        )
        guard proven else { throw AgentAuthenticationError.invalidProof }

        guard let grant = try await tokens.redeem(request.token) else {
            throw AgentAuthenticationError.unknownEnrollmentToken
        }
        guard now < grant.expiresAt else { throw AgentAuthenticationError.enrollmentTokenExpired }

        return EnrolledAgent(
            agent: makeAgentID(),
            server: grant.server,
            publicKey: request.publicKey,
            enrolledAt: now
        )
    }

    /// What to send the agent once its record is persisted.
    ///
    /// - Parameter enrolled: the record ``enroll(_:now:)`` returned.
    /// - Returns: the response, carrying this Manager's identity.
    public func response(for enrolled: EnrolledAgent) -> AgentEnrollmentResponse {
        AgentEnrollmentResponse(agent: enrolled.agent, server: enrolled.server, manager: manager)
    }
}
