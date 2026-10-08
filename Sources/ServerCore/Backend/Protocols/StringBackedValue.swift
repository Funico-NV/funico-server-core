//
//  StringBackedValue.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// A value that is a string on the wire and a distinct type in Swift: identifiers such as
/// ``ServiceID``, and open vocabularies such as ``ServiceBackendKind``.
///
/// Conforming types get, for free:
///
/// - **Bare-string coding.** `"invoices"`, not `{"rawValue": "invoices"}`, so the wire form stays
///   readable in a log and in an OpenAPI spec, and any non-Swift client can produce it.
/// - `Identifiable`, `CustomStringConvertible` and `ExpressibleByStringLiteral`.
///
/// The point of a separate type per identifier is that a ``ServiceID`` cannot be passed where a
/// ``ServerID`` is expected — the compiler catches the mix-up that a bare `String` would let
/// through to a database query or an agent command.
///
/// Every string is accepted. Validation belongs at the boundary that gives a value meaning: the
/// agent, for instance, resolves a ``ServiceID`` through its own allow-list and never treats one as
/// a unit name or a path.
///
/// ```swift
/// public struct WidgetID: StringBackedValue {
///     public let rawValue: String
///     public init(rawValue: String) { self.rawValue = rawValue }
/// }
///
/// let id: WidgetID = "blue"
/// ```
public protocol StringBackedValue:
    Sendable, Hashable, Codable, RawRepresentable, Identifiable,
    CustomStringConvertible, ExpressibleByStringLiteral
where RawValue == String {

    /// Wraps a string. Never fails: every string is a syntactically valid value.
    init(rawValue: String)
}

extension StringBackedValue {

    /// Wraps a string; shorthand for ``init(rawValue:)``.
    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    /// The string itself.
    public var id: String { rawValue }

    /// The string itself, so interpolation reads `invoices` rather than `ServiceID(rawValue: …)`.
    public var description: String { rawValue }

    /// Wraps a string literal.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    // Written out rather than left to the standard library's `RawRepresentable` defaults, which
    // happen to produce the same bare string today. Spelling it out keeps the wire format a
    // decision of this package and not a side effect of overload resolution — the exact trap
    // `ServerJobState` fell into.

    /// Decodes a bare string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    /// Encodes as a bare string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
