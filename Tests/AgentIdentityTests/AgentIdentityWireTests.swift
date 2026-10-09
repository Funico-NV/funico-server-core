//
//  AgentIdentityWireTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Testing
import Foundation
import ServerCore
import ServerCoreTesting

// The wire shapes and the signed bytes. Both cross a process boundary between an agent and a
// Manager that may be on different releases, so these pin the format rather than only checking
// that Swift reads back what Swift wrote.

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try AgentProtocol.encoder.encode(value)
    return try AgentProtocol.decoder.decode(T.self, from: data)
}

private func json(_ value: some Encodable) throws -> [String: Any] {
    let data = try AgentProtocol.encoder.encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private let fixedNonce = AgentChallengeNonce(rawRepresentation: Array(0..<32))

private let fixedChallenge = AgentChallenge(
    nonce: fixedNonce,
    agent: "agent-1",
    audience: "manager.funico.internal",
    issuedAt: Date(timeIntervalSince1970: 1_770_000_000.9),
    expiresAt: Date(timeIntervalSince1970: 1_770_000_030)
)

// MARK: - Signed bytes

@Test func challengeSigningBytesArePinned() {
    // Computed independently of this package (Python's struct.pack). If this fails the format
    // changed, and every deployed agent and Manager disagrees with this build — bump the context
    // string instead.
    let expected = "0000002266756e69636f2e6167656e742d6964656e746974792e6368616c6c656e67652e7631"
        + "00000020000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        + "000000176d616e616765722e66756e69636f2e696e7465726e616c"
        + "000000076167656e742d31"
        + "000000080000000069800e80"
        + "000000080000000069800e9e"
    #expect(hex(fixedChallenge.signingBytes) == expected)
}

@Test func enrollmentSigningBytesArePinned() {
    let key = AgentPublicKey(algorithm: .ed25519, rawRepresentation: [7, 7, 7, 7])
    let expected = "0000002366756e69636f2e6167656e742d6964656e746974792e656e726f6c6c6d656e742e7631"
        + "0000000e666e632d656e726f6c6c2d616263"
        + "000000076564323535313900000004"
        + "07070707"
    #expect(hex(AgentEnrollmentRequest.signingBytes(token: AgentEnrollmentToken(rawValue: "fnc-enroll-abc"), publicKey: key)) == expected)
}

@Test func lengthPrefixesKeepFieldsFromSliding() {
    // Without length prefixes, agent "ab" + audience "c" and agent "a" + audience "bc" would
    // concatenate to the same bytes.
    let one = AgentChallenge(nonce: fixedNonce, agent: "ab", audience: "c", issuedAt: .distantPast, expiresAt: .distantPast)
    let two = AgentChallenge(nonce: fixedNonce, agent: "a", audience: "bc", issuedAt: .distantPast, expiresAt: .distantPast)
    #expect(one.signingBytes != two.signingBytes)
}

@Test func contextsSeparateEnrollmentFromChallenge() {
    #expect(AgentSigningPayload.challengeContext != AgentSigningPayload.enrollmentContext)
    #expect(fixedChallenge.signingBytes.starts(with: [0, 0, 0, 34] + Array(AgentSigningPayload.challengeContext.utf8)))
}

@Test func challengeTimesAreWholeSeconds() {
    #expect(fixedChallenge.issuedAt == Date(timeIntervalSince1970: 1_770_000_000))
    // Truncation is toward the past, before 1970 as after it.
    let early = AgentChallenge(agent: "a", audience: "m", issuedAt: Date(timeIntervalSince1970: -1.5), expiresAt: .distantFuture)
    #expect(early.issuedAt == Date(timeIntervalSince1970: -2))
}

// MARK: - Wire shapes

@Test func challengeEncodesTimesAsIntegerSeconds() throws {
    let object = try json(fixedChallenge)
    #expect(object["issuedAt"] as? Int == 1_770_000_000)
    #expect(object["expiresAt"] as? Int == 1_770_000_030)
    #expect(object["nonce"] as? String == "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
    #expect(object["agent"] as? String == "agent-1")
    #expect(object["audience"] as? String == "manager.funico.internal")

    // Whatever date strategy the encoder has — Foundation's default included — the bytes signed
    // after a round trip are the same.
    let plain = try JSONDecoder().decode(AgentChallenge.self, from: JSONEncoder().encode(fixedChallenge))
    #expect(plain.signingBytes == fixedChallenge.signingBytes)
}

@Test func binaryValuesAreUnpaddedBase64URL() throws {
    let key = AgentPublicKey(algorithm: .ed25519, rawRepresentation: [0xfb, 0xff, 0xfe])
    #expect(try json(key)["key"] as? String == "-__-")
    #expect(key.description == "ed25519:-__-")

    let signature = AgentSignature(rawRepresentation: [0xff])
    #expect(String(decoding: try AgentProtocol.encoder.encode(signature), as: UTF8.self) == "\"_w\"")

    // One spelling per value: padding and the standard alphabet are refused, as is an empty value.
    for bad in ["\"_w==\"", "\"/w\"", "\"\"", "\"not base64!\""] {
        #expect(throws: DecodingError.self) {
            try AgentProtocol.decoder.decode(AgentSignature.self, from: Data(bad.utf8))
        }
    }
}

@Test func modelsRoundTrip() throws {
    let key = MockAgentSigner(keyBytes: Array(repeating: 9, count: 32)).publicKey
    let token = AgentEnrollmentToken.generate()
    let signature = AgentSignature(rawRepresentation: Array(repeating: 3, count: 64))
    let date = Date(timeIntervalSince1970: 1_770_000_000.25)

    #expect(try roundTrip(key) == key)
    #expect(try roundTrip(signature) == signature)
    #expect(try roundTrip(token) == token)
    #expect(try roundTrip(fixedNonce) == fixedNonce)
    #expect(try roundTrip(fixedChallenge) == fixedChallenge)
    #expect(try roundTrip(ManagerID("m")) == "m")

    let grant = AgentEnrollmentGrant(token: token, server: "box-1", expiresAt: date)
    #expect(try roundTrip(grant) == grant)

    let request = AgentEnrollmentRequest(token: token, publicKey: key, proof: signature)
    #expect(try roundTrip(request) == request)

    let response = AgentEnrollmentResponse(agent: "a", server: "box-1", manager: "m")
    #expect(try roundTrip(response) == response)

    let enrolled = EnrolledAgent(agent: "a", server: "box-1", publicKey: key, enrolledAt: date)
    #expect(try roundTrip(enrolled) == enrolled)

    let answer = AgentChallengeResponse(nonce: fixedNonce, agent: "a", signature: signature)
    #expect(try roundTrip(answer) == answer)
}

@Test func enrollmentRequestShape() throws {
    let key = AgentPublicKey(algorithm: .ed25519, rawRepresentation: [1])
    let object = try json(AgentEnrollmentRequest(
        token: AgentEnrollmentToken(rawValue: "fnc-enroll-x"),
        publicKey: key,
        proof: AgentSignature(rawRepresentation: [2])
    ))
    #expect(object["token"] as? String == "fnc-enroll-x")
    #expect(object["proof"] as? String == "Ag")
    let publicKey = try #require(object["publicKey"] as? [String: Any])
    #expect(publicKey["algorithm"] as? String == "ed25519")
    #expect(publicKey["key"] as? String == "AQ")
}

@Test func handshakeFramesRoundTrip() throws {
    let bodies: [AgentHandshakeMessage.Body] = [
        .hello(AgentHello(agent: "agent-1")),
        .challenge(fixedChallenge),
        .response(AgentChallengeResponse(nonce: fixedNonce, agent: "agent-1", signature: AgentSignature(rawRepresentation: [1, 2]))),
        .accepted,
        .rejected(AgentAuthenticationError.replayed.serverCoreError)
    ]
    for body in bodies {
        let frame = AgentHandshakeMessage(body: body)
        #expect(try roundTrip(frame) == frame)
    }

    let object = try json(AgentHandshakeMessage(body: .rejected(AgentAuthenticationError.expired.serverCoreError)))
    #expect(object["type"] as? String == "rejected")
    #expect(object["version"] as? Int == AgentProtocol.version)
    #expect((object["error"] as? [String: Any])?["code"] as? String == "authenticationFailed")

    #expect(try json(AgentHandshakeMessage(body: .accepted)).keys.sorted() == ["type", "version"])
}

@Test func unknownHandshakeFrameDecodesAsUnsupported() throws {
    let data = Data(#"{"version":1,"type":"capabilities","capabilities":{"compression":true}}"#.utf8)
    let frame = try AgentProtocol.decoder.decode(AgentHandshakeMessage.self, from: data)
    #expect(frame.body == .unsupported(type: "capabilities"))

    // …and cannot be sent back.
    #expect(throws: EncodingError.self) { try AgentProtocol.encoder.encode(frame) }
}

@Test func unknownKeyAlgorithmDecodes() throws {
    let data = Data(#"{"algorithm":"p256","key":"AQID"}"#.utf8)
    let key = try AgentProtocol.decoder.decode(AgentPublicKey.self, from: data)
    #expect(key.algorithm == "p256")
    #expect(MockAgentSignatureVerifier().isValidSignature(AgentSignature(rawRepresentation: [1]), of: [], by: key) == false)
}

// MARK: - Secrets and randomness

@Test func enrollmentTokenNeverPrintsItself() {
    let token = AgentEnrollmentToken.generate()
    #expect(token.rawValue.hasPrefix(AgentEnrollmentToken.prefix))
    // 32 random bytes, base64url without padding.
    #expect(token.rawValue.count == AgentEnrollmentToken.prefix.count + 43)

    var dumped = ""
    dump(token, to: &dumped)
    for rendered in ["\(token)", String(reflecting: token), dumped] {
        #expect(!rendered.contains(token.rawValue))
    }
}

@Test func generatedValuesDoNotRepeat() {
    let nonces = Set((0..<1_000).map { _ in AgentChallengeNonce.random() })
    #expect(nonces.count == 1_000)
    #expect(nonces.allSatisfy { $0.rawRepresentation.count == AgentChallengeNonce.byteCount })

    let tokens = Set((0..<1_000).map { _ in AgentEnrollmentToken.generate() })
    #expect(tokens.count == 1_000)
}

@Test func newErrorCodeIsStable() throws {
    #expect(ServerCoreError.Code.authenticationFailed.rawValue == "authenticationFailed")
}
