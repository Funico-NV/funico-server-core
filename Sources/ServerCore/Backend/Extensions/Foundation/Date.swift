//
//  Date.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

extension Date {

    /// Parses the date half of the legacy `"id;iso8601"` wire format.
    ///
    /// Accepts fractional seconds first and falls back to whole seconds, matching what
    /// `funico-invoices-api` has always done. Loosening or tightening this changes what
    /// a shipped iOS build can read back out of `@AppStorage`.
    static func fromISO8601String(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// The exact string `funico-invoices-service` puts on the wire today.
    ///
    /// - Important: byte-for-byte compatibility is the requirement here, not merely
    ///   round-tripping. This is `@AppStorage`'s persistence codec on real devices, and
    ///   the service cannot be upgraded atomically with an App Store build.
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
