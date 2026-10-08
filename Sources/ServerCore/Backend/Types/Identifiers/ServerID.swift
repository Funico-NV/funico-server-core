//
//  ServerID.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Identifies one host the Server Manager knows about — a slug such as `"funapi-01"`.
///
/// Assigned by the Manager when an administrator adds the server, and stable for its lifetime.
/// Not a hostname or an address: a server keeps its ID when its address changes.
public struct ServerID: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
