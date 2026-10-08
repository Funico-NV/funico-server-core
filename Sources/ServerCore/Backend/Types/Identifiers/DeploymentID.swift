//
//  DeploymentID.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Identifies one attempt to put a release of a service into production.
///
/// Minted by the Manager when a deployment is requested. Retrying the same deployment reuses the
/// ID; deploying the same release again later is a new deployment with a new ID.
public struct DeploymentID: StringBackedValue {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension DeploymentID {

    /// A new, random deployment ID.
    public init() {
        self.init(rawValue: UUID().uuidString.lowercased())
    }
}
