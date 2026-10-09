//
//  Base64URL.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Base64url without padding (RFC 4648 §5), the wire form of every binary value in the agent
/// identity protocol: keys, signatures, nonces and enrollment tokens.
///
/// URL-safe so a token survives a command line, a URL or a copy from a chat message unchanged, and
/// strict on decode — only the URL alphabet, no padding — so each value has exactly one spelling.
enum Base64URL {

    static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> [UInt8]? {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard string.allSatisfy({ alphabet.contains($0) }) else { return nil }

        var standard = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder != 0 {
            standard += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: standard) else { return nil }
        return [UInt8](data)
    }

    /// Random bytes from the system CSPRNG.
    ///
    /// `SystemRandomNumberGenerator` is documented as cryptographically secure on every platform
    /// Swift supports — `arc4random_buf` on Apple platforms, `getrandom` on Linux,
    /// `BCryptGenRandom` on Windows — which is what lets nonces and tokens be minted here without a
    /// crypto dependency.
    static func randomBytes(_ count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    static func decode<Key: CodingKey>(
        _ string: String,
        in container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> [UInt8] {
        guard let bytes = decode(string), !bytes.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "expected non-empty unpadded base64url"
            )
        }
        return bytes
    }

    static func decode(from decoder: any Decoder) throws -> [UInt8] {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let bytes = decode(string), !bytes.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected non-empty unpadded base64url"
            )
        }
        return bytes
    }
}
