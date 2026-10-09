//
//  ManagerID.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Identifies one Server Manager deployment: the *audience* of every challenge it issues.
///
/// An agent learns it once, from ``AgentEnrollmentResponse/manager``, and from then on signs only
/// challenges naming it. A challenge's signature therefore cannot be lifted from one Manager and
/// presented to another — a staging Manager, say, that an operator also enrolled the host with.
///
/// Choose a value that never changes for the life of the deployment, such as
/// `"manager.funico.internal"`. Renaming it invalidates every enrolled agent's notion of who it
/// talks to, and each would have to be enrolled again.
public struct ManagerID: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
