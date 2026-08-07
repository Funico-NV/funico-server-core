//
//  ServerJob.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// A named unit of work a server runs — `"Process"`, `"Lookup"`, a reconcile, a nightly
/// export. One per server vocabulary, not one closed set for all of them.
///
/// This is a `String`-backed struct rather than an enum, following `Notification.Name`, and
/// the reason is `@AppStorage`: it requires `RawRepresentable where RawValue == String`, so
/// a protocol or an existential loses persistence entirely. A closed enum would keep
/// `@AppStorage` but would mean every new managed server needs a foundation release and a
/// recompiled app.
///
/// Per-server vocabularies are additive extensions:
///
/// ```swift
/// extension ServerJob {
///     public static let process = ServerJob("Process")
///     public static let lookup  = ServerJob("Lookup")
/// }
/// ```
///
/// - Note: deliberately no `allCases`. What the app should show comes from
///   ``ServerJobDescriptor`` over `GET /v1/servers/{id}/jobs` at runtime, which is what
///   makes N servers work without shipping a new build.
public struct ServerJob: Sendable, Hashable, RawRepresentable, Identifiable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var id: String { rawValue }
}

extension ServerJob: Codable {

    // Encoded as a bare string rather than `{"rawValue": …}`, so the wire form is the job
    // name itself and stays readable in a spec and in a log.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ServerJob: CustomStringConvertible {

    public var description: String { rawValue }
}

extension ServerJob: ExpressibleByStringLiteral {

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}
