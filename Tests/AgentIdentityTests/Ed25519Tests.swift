//
//  Ed25519Tests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

#if Crypto
import Testing
import Foundation
import ServerCore
import ServerCoreCrypto
import ServerCoreTesting

// What only the real implementation can show: that it is standard Ed25519, that keys survive
// persistence, and that the mock and the real scheme never accept each other's keys.

private func bytes(_ hex: String) -> [UInt8] {
    var result: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        result.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return result
}

@Test func matchesRFC8032TestVector() throws {
    // RFC 8032 §7.1, TEST 1: the empty message.
    let signer = try Ed25519AgentSigner(rawRepresentation: bytes("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
    #expect(signer.publicKey == AgentPublicKey(
        algorithm: .ed25519,
        rawRepresentation: bytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
    ))

    let signature = AgentSignature(rawRepresentation: bytes(
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
    ))
    let verifier = Ed25519AgentSignatureVerifier()
    #expect(verifier.isValidSignature(signature, of: [], by: signer.publicKey))
    #expect(!verifier.isValidSignature(signature, of: [0], by: signer.publicKey))
}

@Test func privateKeySurvivesPersistence() async throws {
    let signer = Ed25519AgentSigner()
    #expect(signer.rawRepresentation.count == 32)

    let loaded = try Ed25519AgentSigner(rawRepresentation: signer.rawRepresentation)
    #expect(loaded.publicKey == signer.publicKey)

    let signature = try loaded.sign([1, 2, 3])
    #expect(signature.rawRepresentation.count == 64)
    #expect(Ed25519AgentSignatureVerifier().isValidSignature(signature, of: [1, 2, 3], by: signer.publicKey))
}

@Test func malformedKeysAndSignaturesAreRefused() throws {
    let signer = Ed25519AgentSigner()
    let verifier = Ed25519AgentSignatureVerifier()
    let signature = try signer.sign([1])

    var truncatedKey = signer.publicKey
    truncatedKey.rawRepresentation.removeLast()
    #expect(!verifier.isValidSignature(signature, of: [1], by: truncatedKey))

    var truncatedSignature = signature
    truncatedSignature.rawRepresentation.removeLast()
    #expect(!verifier.isValidSignature(truncatedSignature, of: [1], by: signer.publicKey))

    var relabelled = signer.publicKey
    relabelled.algorithm = "ed448"
    #expect(!verifier.isValidSignature(signature, of: [1], by: relabelled))
}

@Test func mockAndRealSchemesRejectEachOther() throws {
    let mock = MockAgentSigner()
    let real = Ed25519AgentSigner()
    let mockSignature = mock.sign([1])
    let realSignature = try real.sign([1])

    #expect(!Ed25519AgentSignatureVerifier().isValidSignature(mockSignature, of: [1], by: mock.publicKey))
    #expect(!MockAgentSignatureVerifier().isValidSignature(realSignature, of: [1], by: real.publicKey))
}
#endif
