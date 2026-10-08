//
//  ServiceID.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Identifies one managed service on a host — a slug such as `"invoices"`.
///
/// This is a *name the host has agreed to*, not a systemd unit and not a path. The agent resolves
/// it through its local, root-owned allow-list, which is the only place a unit name or an install
/// directory comes from. A ``ServiceID`` the allow-list does not contain is refused with
/// ``ServerCoreError/Code/unknownService``, so a compromised Manager can only ever refer to
/// services the host already lists.
public struct ServiceID: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
