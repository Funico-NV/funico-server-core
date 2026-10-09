//
//  AgentSigningPayload.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The exact bytes an agent signs: the canonical, domain-separated encoding behind every
/// ``AgentSignature``.
///
/// Every payload has the same shape — a sequence of fields, each written as its length followed by
/// its bytes, the first field always a context string naming what is being signed:
///
/// ```
/// payload = field(context) ‖ field(f₁) ‖ … ‖ field(fₙ)
/// field   = UInt32 big-endian byte count ‖ bytes
/// string  = UTF-8, exactly as stored (no Unicode normalisation)
/// time    = Int64 big-endian, whole seconds since 1970-01-01T00:00:00Z
/// ```
///
/// | Context | Fields, in order |
/// |---|---|
/// | ``challengeContext`` | nonce, audience (`ManagerID`), agent (`AgentID`), issued-at, expires-at |
/// | ``enrollmentContext`` | token, key algorithm, public key |
///
/// Why each choice, because each one looks arbitrary and each one is load-bearing:
///
/// - **Not JSON.** A signature is over bytes, and two correct JSON encoders disagree about key
///   order, whitespace, escaping (`/` or `\/`), and how a number or a date is spelled. The agent
///   and the Manager would each have to re-encode the same value identically on different
///   platforms and toolchains, forever. A fixed binary layout has one spelling.
/// - **Length-prefixed.** Concatenation alone is ambiguous: `nonce ‖ agentID ‖ timestamp` with a
///   variable-length agent ID lets bytes slide from one field into the next, so two different
///   challenges can produce the same signed bytes. A length prefix on every field makes the
///   encoding injective.
/// - **Domain-separated.** The same key signs enrollment proofs and challenge responses, and may
///   sign more later. Leading with a context string that differs per purpose means a signature
///   made for one can never verify as another, whatever the other fields hold.
/// - **Fixed field order, versioned context.** The order is part of the format, and the `v1` in the
///   context is its version. Changing a field means a new context string, never a reinterpretation
///   of the old one — an agent and a Manager on different releases must agree on these bytes.
/// - **Whole seconds.** A `Date` is a `Double`; through ISO 8601 or a JSON number it does not
///   survive bit-for-bit, and a signature over a value one end rounded differently fails. Times are
///   truncated to whole seconds when an ``AgentChallenge`` is created and travel as integers.
///
/// The layout is frozen: tests pin it byte for byte.
public enum AgentSigningPayload {

    /// The context string that opens a challenge response's signed bytes. See
    /// ``AgentChallenge/signingBytes``.
    public static let challengeContext = "funico.agent-identity.challenge.v1"

    /// The context string that opens an enrollment proof's signed bytes. See
    /// ``AgentEnrollmentRequest/signingBytes(token:publicKey:)``.
    public static let enrollmentContext = "funico.agent-identity.enrollment.v1"
}

/// Writes the length-prefixed fields ``AgentSigningPayload`` describes.
struct CanonicalWriter {

    private(set) var bytes: [UInt8] = []

    init(context: String) {
        append(context)
    }

    mutating func append(_ field: [UInt8]) {
        precondition(field.count <= Int(UInt32.max), "a signed field cannot exceed 4 GiB")
        let length = UInt32(field.count)
        bytes += [
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length)
        ]
        bytes += field
    }

    mutating func append(_ string: String) {
        append(Array(string.utf8))
    }

    mutating func append(_ value: Int64) {
        let bits = UInt64(bitPattern: value)
        append((0..<8).reversed().map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) })
    }
}
