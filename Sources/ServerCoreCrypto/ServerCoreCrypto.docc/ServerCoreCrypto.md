# ``ServerCoreCrypto``

Ed25519 signing for agents and verification for the Manager: the real implementation of
`ServerCore`'s `AgentSigner` and `AgentSignatureVerifier`.

## Overview

`ServerCore` owns the agent identity protocol — the wire models, the canonical signed bytes, and
every check the Manager makes — but has no package dependencies and so no cryptography. This module
supplies it, with swift-crypto's `Curve25519.Signing`: CryptoKit on Apple platforms, swift-crypto's
own BoringSSL-derived implementation on Linux and Windows. The signatures are standard RFC 8032
Ed25519 either way, and a test checks one against the RFC's own vector.

It is compiled only with the package's `Crypto` trait. A consumer that leaves the trait off — the
app, a managed server — never resolves swift-crypto; the agent and the Manager API enable it:

```swift
.package(
    url: "https://github.com/Funico-NV/funico-server-core",
    from: Version(3, 1, 0),
    traits: ["Crypto"]
)
```

```swift
import ServerCore
import ServerCoreCrypto

let manager: ManagerID = "manager.funico.internal"
let verifier = Ed25519AgentSignatureVerifier()

// The agent, once: a key pair. Persist `signer.rawRepresentation` with mode 0600; it never leaves
// the host.
let signer = Ed25519AgentSigner()

// The Manager enrolls it with a one-time token an administrator carried to the host.
let enrollment = AgentEnrollmentAuthority(
    manager: manager,
    tokens: InMemoryAgentEnrollmentTokenStore(),
    verifier: verifier
)
let grant = try await enrollment.issueToken(for: "box-1")
let enrolled = try await enrollment.enroll(
    try await AgentEnrollmentRequest(token: grant.token, signer: signer)
)
let identity = enrollment.response(for: enrolled)

// Every connection: challenge, signature, verification.
let authenticator = AgentAuthenticator(
    manager: manager,
    verifier: verifier,
    nonces: InMemoryAgentNonceStore()
)
let challenge = authenticator.challenge(for: identity.agent)
let response = try await challenge.response(as: identity.agent, for: identity.manager, signer: signer)
try await authenticator.verify(response, to: challenge, from: enrolled)
```

The verifier refuses, before attempting verification, any key whose algorithm is not `ed25519`, a
key that is not 32 bytes and a signature that is not 64. A `MockAgentSigner` key from
`ServerCoreTesting` is therefore refused too, so a test double cannot be enrolled with a real
Manager by mistake.

## Topics

### Signing and verifying

- ``Ed25519AgentSigner``
- ``Ed25519AgentSignatureVerifier``
