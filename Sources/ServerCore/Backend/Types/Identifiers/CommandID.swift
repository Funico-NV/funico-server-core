//
//  CommandID.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Identifies one command sent from the Manager to an agent, and is what makes commands
/// idempotent.
///
/// The agent journals every ``CommandID`` it has accepted. A command re-sent with the same ID —
/// after a reconnect, say — gets the stored result back instead of running a second time. A
/// restart that the Manager could not confirm is therefore safe to resend.
///
/// Generate a fresh one per command with ``init()``.
public struct CommandID: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CommandID {

    /// A new, random command ID.
    public init() {
        self.init(rawValue: UUID().uuidString.lowercased())
    }
}
