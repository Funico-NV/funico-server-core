# Enrolling and authenticating agents

How an agent gets an identity once, and proves it on every connection — with no shared secret on
either side.

## Overview

An agent's identity is an Ed25519 key pair generated on its own host. The private key never leaves
that host; the Manager stores only the public key, bound to an ``AgentID``. Two exchanges use it:

- **Enrollment**, once per host. An administrator gets a one-time ``AgentEnrollmentToken`` from the
  Manager and runs the agent's `enroll` command with it. The agent sends the token, its public key
  and a proof that it holds the private key; the Manager binds the key to a new ``AgentID``.
- **The handshake**, on every connection. The Manager sends an ``AgentChallenge``; the agent signs
  it; the Manager checks the signature against the enrolled key, and that the challenge is fresh,
  unanswered, for this agent and for this Manager.

Revoking an agent is deleting its ``EnrolledAgent`` record. There is no token or password to
rotate, on the host or on the Manager.

### Where the cryptography lives

`ServerCore` has zero package dependencies, so it signs and verifies nothing itself. Everything
that is *policy* — the wire models, the exact bytes signed, the order of checks, expiry, single
use — is here, behind three protocols:

| Protocol | Implemented by |
|---|---|
| ``AgentSigner`` | `Ed25519AgentSigner` in `ServerCoreCrypto` (the agent); `MockAgentSigner` in `ServerCoreTesting` |
| ``AgentSignatureVerifier`` | `Ed25519AgentSignatureVerifier` in `ServerCoreCrypto` (the Manager); `MockAgentSignatureVerifier` |
| ``AgentNonceStore``, ``AgentEnrollmentTokenStore`` | ``InMemoryAgentNonceStore``, ``InMemoryAgentEnrollmentTokenStore``, or the Manager's database |

`ServerCoreCrypto` uses swift-crypto and is behind the `Crypto` trait, so a consumer that never
signs anything — the app, a managed server — does not resolve swift-crypto at all.

### Enrollment

```swift
import Foundation
import ServerCore

// The Manager, when an administrator adds a server. Show the token once; never log it.
func addServer(_ server: ServerID, enrollment: AgentEnrollmentAuthority) async throws -> String {
    let grant = try await enrollment.issueToken(for: server)
    return grant.token.rawValue
}

// The agent, on the host: `funico-server-agent enroll --token fnc-enroll-…`.
func enrollmentRequest(token: String, signer: any AgentSigner) async throws -> AgentEnrollmentRequest {
    try await AgentEnrollmentRequest(token: AgentEnrollmentToken(rawValue: token), signer: signer)
}

// The Manager, receiving that request.
func enroll(
    _ request: AgentEnrollmentRequest,
    enrollment: AgentEnrollmentAuthority
) async throws -> AgentEnrollmentResponse {
    let enrolled = try await enrollment.enroll(request)
    // Persist `enrolled` before answering; its public key is what every connection verifies.
    return enrollment.response(for: enrolled)
}
```

A token is single use and lives fifteen minutes (``AgentEnrollmentAuthority/defaultTokenLifetime``).
The request's proof of possession is checked *before* the token is redeemed, so a garbled request
does not burn the operator's token; an expired token is redeemed — and so spent — before it is
refused.

### The handshake

```
agent   → hello      { agent }
Manager → challenge  { nonce, agent, audience, issuedAt, expiresAt }
agent   → response   { nonce, agent, signature }
Manager → accepted                       or   rejected { code: authenticationFailed }
```

Each frame is an ``AgentHandshakeMessage``. Until `accepted`, neither end sends or acts on anything
else; after it, the connection carries ``AgentMessage`` and ``ManagerMessage`` frames as described
in <doc:AgentProtocolArticle>.

```swift
import Foundation
import ServerCore

// The Manager, on hello. Keep the challenge with the connection.
func challenge(_ hello: AgentHello, authenticator: AgentAuthenticator) -> AgentChallenge {
    authenticator.challenge(for: hello.agent)
}

// The agent, with the identity its enrollment returned.
func answer(
    _ challenge: AgentChallenge,
    identity: AgentEnrollmentResponse,
    signer: any AgentSigner
) async throws -> AgentChallengeResponse {
    try await challenge.response(as: identity.agent, for: identity.manager, signer: signer)
}

// The Manager, on response: verify against the challenge it kept, never one echoed back.
func authenticate(
    _ response: AgentChallengeResponse,
    to challenge: AgentChallenge,
    enrolled: EnrolledAgent,
    authenticator: AgentAuthenticator
) async -> AgentHandshakeMessage {
    do {
        try await authenticator.verify(response, to: challenge, from: enrolled)
        return AgentHandshakeMessage(body: .accepted)
    } catch let error as AgentAuthenticationError {
        // Log `error`; the peer learns only `authenticationFailed`.
        return AgentHandshakeMessage(body: .rejected(error.serverCoreError))
    } catch {
        return AgentHandshakeMessage(body: .rejected(ServerCoreError(.backendFailure, "try again")))
    }
}
```

``AgentAuthenticator/verify(_:to:from:now:)`` refuses, in this order, a response to a different
challenge, any mismatch of agent ID, a challenge for another Manager, a challenge outside its
thirty-second window, a challenge already answered once, and a signature that does not verify
against the enrolled key. The nonce is consumed before the signature is checked: a challenge gets
one attempt, right or wrong.

The agent checks the agent ID and the audience before it signs, but never the expiry — its clock
is not the Manager's, and only the Manager, which issued the challenge, can judge it.

### The signed bytes

What is signed is not JSON. It is the canonical encoding ``AgentSigningPayload`` describes: a
context string naming the purpose, then each field as a big-endian length and its bytes, in a fixed
order, with times as whole Unix seconds. That makes the bytes independent of any encoder's key
order, escaping or date format; unambiguous where fields of variable length meet; and impossible
to reuse across purposes, since an enrollment proof and a challenge response open with different
contexts. Tests pin the layout byte for byte; changing it means a new context string.
