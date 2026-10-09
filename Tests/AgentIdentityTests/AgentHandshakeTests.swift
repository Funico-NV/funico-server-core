//
//  AgentHandshakeTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Testing
import Foundation
import ServerCore
import ServerCoreTesting
#if Crypto
import ServerCoreCrypto
#endif

// The handshake and enrollment policy, run once per signature scheme: always against the mock (so
// the policy is tested on every `swift test`), and against real Ed25519 when the `Crypto` trait is
// on. The policy must not depend on which scheme is behind the protocols.

struct Scheme: Sendable, CustomTestStringConvertible {
    let name: String
    let makeSigner: @Sendable () -> any AgentSigner
    let verifier: any AgentSignatureVerifier

    var testDescription: String { name }

    static let all: [Scheme] = {
        var schemes = [
            Scheme(name: "mock", makeSigner: { MockAgentSigner() }, verifier: MockAgentSignatureVerifier())
        ]
        #if Crypto
        schemes.append(
            Scheme(name: "ed25519", makeSigner: { Ed25519AgentSigner() }, verifier: Ed25519AgentSignatureVerifier())
        )
        #endif
        return schemes
    }()
}

private let manager: ManagerID = "manager.funico.internal"
private let now = Date(timeIntervalSince1970: 1_770_000_000.75)

/// Everything one test needs: a Manager with both authorities, and an agent enrolled with it.
private struct Fixture: Sendable {
    let scheme: Scheme
    let enrollment: AgentEnrollmentAuthority
    let authenticator: AgentAuthenticator
    let signer: any AgentSigner
    let enrolled: EnrolledAgent
    let reply: AgentEnrollmentResponse

    init(_ scheme: Scheme, nonces: any AgentNonceStore = InMemoryAgentNonceStore()) async throws {
        self.scheme = scheme
        enrollment = AgentEnrollmentAuthority(
            manager: manager,
            tokens: InMemoryAgentEnrollmentTokenStore(),
            verifier: scheme.verifier
        )
        authenticator = AgentAuthenticator(manager: manager, verifier: scheme.verifier, nonces: nonces)
        signer = scheme.makeSigner()

        let grant = try await enrollment.issueToken(for: "box-1", now: now)
        let request = try await AgentEnrollmentRequest(token: grant.token, signer: signer)
        enrolled = try await enrollment.enroll(request, now: now.addingTimeInterval(60))
        reply = enrollment.response(for: enrolled)
    }

    /// One full connection: challenge, agent answers, Manager verifies.
    func handshake(at time: Date = now) async throws {
        let challenge = authenticator.challenge(for: reply.agent, now: time)
        let response = try await challenge.response(as: reply.agent, for: reply.manager, signer: signer)
        try await authenticator.verify(response, to: challenge, from: enrolled, now: time)
    }
}

// MARK: - The handshake

@Test(arguments: Scheme.all)
func validHandshakeSucceeds(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)

    #expect(fixture.reply.server == "box-1")
    #expect(fixture.reply.manager == manager)
    #expect(fixture.enrolled.publicKey == fixture.signer.publicKey)

    try await fixture.handshake()
    // Every connection gets its own challenge, so authenticating again simply works.
    try await fixture.handshake(at: now.addingTimeInterval(5))
}

@Test(arguments: Scheme.all)
func handshakeSurvivesTheWire(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)

    // Every frame goes through JSON, as it would over the socket. The Manager keeps its own copy of
    // the challenge; the agent signs the copy it decoded. They must produce identical signed bytes.
    func wire(_ body: AgentHandshakeMessage.Body) throws -> AgentHandshakeMessage.Body {
        let data = try AgentProtocol.encoder.encode(AgentHandshakeMessage(body: body))
        return try AgentProtocol.decoder.decode(AgentHandshakeMessage.self, from: data).body
    }

    guard case .hello(let hello) = try wire(.hello(AgentHello(agent: fixture.reply.agent))) else {
        Issue.record("hello did not survive"); return
    }
    let kept = fixture.authenticator.challenge(for: hello.agent, now: now)
    guard case .challenge(let received) = try wire(.challenge(kept)) else {
        Issue.record("challenge did not survive"); return
    }
    let answer = try await received.response(as: fixture.reply.agent, for: fixture.reply.manager, signer: fixture.signer)
    guard case .response(let response) = try wire(.response(answer)) else {
        Issue.record("response did not survive"); return
    }

    try await fixture.authenticator.verify(response, to: kept, from: fixture.enrolled, now: now)
}

@Test(arguments: Scheme.all)
func replayedResponseIsRejected(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let challenge = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)
    let response = try await challenge.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)

    try await fixture.authenticator.verify(response, to: challenge, from: fixture.enrolled, now: now)

    // The same response to the same challenge — a captured frame, replayed.
    await #expect(throws: AgentAuthenticationError.replayed) {
        try await fixture.authenticator.verify(response, to: challenge, from: fixture.enrolled, now: now)
    }

    // The same response against the next connection's challenge.
    let next = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)
    await #expect(throws: AgentAuthenticationError.challengeMismatch) {
        try await fixture.authenticator.verify(response, to: next, from: fixture.enrolled, now: now)
    }

    // …and with its nonce rewritten to match: the old signature does not cover the new nonce.
    var rewritten = response
    rewritten.nonce = next.nonce
    await #expect(throws: AgentAuthenticationError.invalidSignature) {
        try await fixture.authenticator.verify(rewritten, to: next, from: fixture.enrolled, now: now)
    }
}

@Test(arguments: Scheme.all)
func eachChallengeGetsOneAttempt(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let challenge = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)

    let forged = try await challenge.response(as: fixture.reply.agent, for: manager, signer: scheme.makeSigner())
    await #expect(throws: AgentAuthenticationError.invalidSignature) {
        try await fixture.authenticator.verify(forged, to: challenge, from: fixture.enrolled, now: now)
    }

    // A failed attempt spends the challenge: no second guess, even a correct one.
    let genuine = try await challenge.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)
    await #expect(throws: AgentAuthenticationError.replayed) {
        try await fixture.authenticator.verify(genuine, to: challenge, from: fixture.enrolled, now: now)
    }
}

@Test(arguments: Scheme.all)
func wrongKeySignatureIsRejected(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let challenge = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)

    // A different key claiming to be the enrolled agent.
    let impostor = scheme.makeSigner()
    let response = try await challenge.response(as: fixture.reply.agent, for: manager, signer: impostor)

    await #expect(throws: AgentAuthenticationError.invalidSignature) {
        try await fixture.authenticator.verify(response, to: challenge, from: fixture.enrolled, now: now)
    }
}

@Test(arguments: Scheme.all)
func signatureOverAlteredChallengeIsRejected(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let issued = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)

    // The agent is handed a challenge with a later expiry than the one issued. The Manager verifies
    // against what it kept, so the signature over the altered copy does not verify.
    var altered = issued
    altered.expiresAt = issued.expiresAt.addingTimeInterval(3600)
    let response = try await altered.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)

    await #expect(throws: AgentAuthenticationError.invalidSignature) {
        try await fixture.authenticator.verify(response, to: issued, from: fixture.enrolled, now: now)
    }
}

@Test(arguments: Scheme.all)
func expiredChallengeIsRejected(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let challenge = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)
    let response = try await challenge.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)

    #expect(challenge.expiresAt.timeIntervalSince(challenge.issuedAt) == AgentAuthenticator.defaultChallengeLifetime)

    // At the expiry instant it is already too late; the window is half-open.
    await #expect(throws: AgentAuthenticationError.expired) {
        try await fixture.authenticator.verify(response, to: challenge, from: fixture.enrolled, now: challenge.expiresAt)
    }
    // Before it was issued — the Manager's clock stepped back — is refused too.
    await #expect(throws: AgentAuthenticationError.expired) {
        try await fixture.authenticator.verify(
            response, to: challenge, from: fixture.enrolled, now: challenge.issuedAt.addingTimeInterval(-1)
        )
    }
    // An expired attempt does not spend the nonce; the expiry check alone refuses it forever after.
    try await fixture.authenticator.verify(
        response, to: challenge, from: fixture.enrolled, now: challenge.expiresAt.addingTimeInterval(-1)
    )
}

@Test(arguments: Scheme.all)
func challengeForAnotherAgentIsRejected(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let other = try await Fixture(scheme)

    // The connection claims to be the other agent; this one signs with its own key.
    let forOther = fixture.authenticator.challenge(for: other.reply.agent, now: now)

    // The agent refuses to sign a challenge addressed to someone else.
    await #expect(throws: AgentAuthenticationError.wrongAgent) {
        _ = try await forOther.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)
    }

    // A response naming itself, to a challenge for the other agent.
    let signed = AgentChallengeResponse(
        nonce: forOther.nonce,
        agent: fixture.reply.agent,
        signature: try await fixture.signer.sign(forOther.signingBytes)
    )
    await #expect(throws: AgentAuthenticationError.wrongAgent) {
        try await fixture.authenticator.verify(signed, to: forOther, from: other.enrolled, now: now)
    }

    // A correctly signed response, checked against the wrong enrolled record.
    let own = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)
    let response = try await own.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)
    await #expect(throws: AgentAuthenticationError.wrongAgent) {
        try await fixture.authenticator.verify(response, to: own, from: other.enrolled, now: now)
    }
}

@Test(arguments: Scheme.all)
func challengeForAnotherAudienceIsRejected(scheme: Scheme) async throws {
    let fixture = try await Fixture(scheme)
    let staging = AgentAuthenticator(
        manager: "staging.funico.internal",
        verifier: scheme.verifier,
        nonces: InMemoryAgentNonceStore()
    )
    let foreign = staging.challenge(for: fixture.reply.agent, now: now)

    // The agent will not sign for a Manager it did not enroll with.
    await #expect(throws: AgentAuthenticationError.wrongAudience) {
        _ = try await foreign.response(as: fixture.reply.agent, for: fixture.reply.manager, signer: fixture.signer)
    }

    // And a signature made for the staging Manager is refused by this one.
    let response = try await foreign.response(as: fixture.reply.agent, for: "staging.funico.internal", signer: fixture.signer)
    await #expect(throws: AgentAuthenticationError.wrongAudience) {
        try await fixture.authenticator.verify(response, to: foreign, from: fixture.enrolled, now: now)
    }
}

@Test func failuresReachThePeerAsOneGenericCode() {
    let reasons: [AgentAuthenticationError] = [
        .challengeMismatch, .wrongAgent, .wrongAudience, .expired, .replayed, .invalidSignature,
        .unknownEnrollmentToken, .enrollmentTokenExpired, .invalidProof
    ]
    let sent = Set(reasons.map(\.serverCoreError))
    #expect(sent == [ServerCoreError(.authenticationFailed, "agent authentication failed")])
}

@Test func nonceStoreForgetsOnlyAfterExpiry() async {
    let store = InMemoryAgentNonceStore()
    let nonce = AgentChallengeNonce.random()
    let expiry = now.addingTimeInterval(30)

    #expect(await store.consume(nonce, expiresAt: expiry, now: now))
    #expect(await !store.consume(nonce, expiresAt: expiry, now: now.addingTimeInterval(29)))
    #expect(await store.count == 1)

    // Past expiry the entry is pruned; the authenticator's expiry check is what refuses it then.
    #expect(await store.consume(.random(), expiresAt: now.addingTimeInterval(90), now: expiry))
    #expect(await store.count == 1)
}

@Test func concurrentAnswersToOneChallengeAcceptOnlyOne() async throws {
    let fixture = try await Fixture(Scheme.all[0])
    let challenge = fixture.authenticator.challenge(for: fixture.reply.agent, now: now)
    let response = try await challenge.response(as: fixture.reply.agent, for: manager, signer: fixture.signer)

    let accepted = await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<20 {
            group.addTask {
                (try? await fixture.authenticator.verify(response, to: challenge, from: fixture.enrolled, now: now)) != nil
            }
        }
        return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
    }
    #expect(accepted == 1)
}

// MARK: - Enrollment

@Test(arguments: Scheme.all)
func enrollmentTokenIsSingleUse(scheme: Scheme) async throws {
    let tokens = InMemoryAgentEnrollmentTokenStore()
    let authority = AgentEnrollmentAuthority(manager: manager, tokens: tokens, verifier: scheme.verifier)
    let grant = try await authority.issueToken(for: "box-1", now: now)

    let first = try await AgentEnrollmentRequest(token: grant.token, signer: scheme.makeSigner())
    _ = try await authority.enroll(first, now: now)
    #expect(await tokens.outstanding.isEmpty)

    // The same token again — even with the very same request — is refused.
    await #expect(throws: AgentAuthenticationError.unknownEnrollmentToken) {
        _ = try await authority.enroll(first, now: now)
    }
    let second = try await AgentEnrollmentRequest(token: grant.token, signer: scheme.makeSigner())
    await #expect(throws: AgentAuthenticationError.unknownEnrollmentToken) {
        _ = try await authority.enroll(second, now: now)
    }
}

@Test(arguments: Scheme.all)
func enrollmentMintsADistinctIdentityEachTime(scheme: Scheme) async throws {
    let authority = AgentEnrollmentAuthority(manager: manager, tokens: InMemoryAgentEnrollmentTokenStore(), verifier: scheme.verifier)

    var agents: Set<AgentID> = []
    for _ in 0..<3 {
        let grant = try await authority.issueToken(for: "box-1", now: now)
        let request = try await AgentEnrollmentRequest(token: grant.token, signer: scheme.makeSigner())
        agents.insert(try await authority.enroll(request, now: now).agent)
    }
    #expect(agents.count == 3)
}

@Test(arguments: Scheme.all)
func expiredEnrollmentTokenIsRejectedAndSpent(scheme: Scheme) async throws {
    let tokens = InMemoryAgentEnrollmentTokenStore()
    let authority = AgentEnrollmentAuthority(manager: manager, tokens: tokens, verifier: scheme.verifier)
    let grant = try await authority.issueToken(for: "box-1", now: now)
    #expect(grant.expiresAt == now.addingTimeInterval(AgentEnrollmentAuthority.defaultTokenLifetime))

    let request = try await AgentEnrollmentRequest(token: grant.token, signer: scheme.makeSigner())
    await #expect(throws: AgentAuthenticationError.enrollmentTokenExpired) {
        _ = try await authority.enroll(request, now: grant.expiresAt)
    }
    await #expect(throws: AgentAuthenticationError.unknownEnrollmentToken) {
        _ = try await authority.enroll(request, now: now)
    }
}

@Test(arguments: Scheme.all)
func invalidProofIsRejectedWithoutSpendingTheToken(scheme: Scheme) async throws {
    let tokens = InMemoryAgentEnrollmentTokenStore()
    let authority = AgentEnrollmentAuthority(manager: manager, tokens: tokens, verifier: scheme.verifier)
    let grant = try await authority.issueToken(for: "box-1", now: now)
    let signer = scheme.makeSigner()
    let valid = try await AgentEnrollmentRequest(token: grant.token, signer: signer)

    // The key swapped for another: the proof was made by a different key.
    var swapped = valid
    swapped.publicKey = scheme.makeSigner().publicKey
    await #expect(throws: AgentAuthenticationError.invalidProof) {
        _ = try await authority.enroll(swapped, now: now)
    }

    // A proof made for a different token.
    let other = try await AgentEnrollmentRequest(token: .generate(), signer: signer)
    var mismatched = valid
    mismatched.proof = other.proof
    await #expect(throws: AgentAuthenticationError.invalidProof) {
        _ = try await authority.enroll(mismatched, now: now)
    }

    // Neither reached the store, so the operator's token still works.
    #expect(await tokens.outstanding == [grant])
    _ = try await authority.enroll(valid, now: now)
}

@Test(arguments: Scheme.all)
func unissuedTokenIsRejected(scheme: Scheme) async throws {
    let authority = AgentEnrollmentAuthority(manager: manager, tokens: InMemoryAgentEnrollmentTokenStore(), verifier: scheme.verifier)
    let request = try await AgentEnrollmentRequest(token: .generate(), signer: scheme.makeSigner())
    await #expect(throws: AgentAuthenticationError.unknownEnrollmentToken) {
        _ = try await authority.enroll(request, now: now)
    }
}

@Test func revokedAgentCannotAuthenticate() async throws {
    // Revocation is deleting the record. A re-enrolled host gets a new identity and key; the old
    // key no longer verifies for it.
    let fixture = try await Fixture(Scheme.all[0])
    let grant = try await fixture.enrollment.issueToken(for: "box-1", now: now)
    let fresh = MockAgentSigner()
    let reenrolled = try await fixture.enrollment.enroll(
        try await AgentEnrollmentRequest(token: grant.token, signer: fresh),
        now: now
    )
    #expect(reenrolled.agent != fixture.enrolled.agent)

    let challenge = fixture.authenticator.challenge(for: reenrolled.agent, now: now)
    let stale = try await challenge.response(as: reenrolled.agent, for: manager, signer: fixture.signer)
    await #expect(throws: AgentAuthenticationError.invalidSignature) {
        try await fixture.authenticator.verify(stale, to: challenge, from: reenrolled, now: now)
    }
}
