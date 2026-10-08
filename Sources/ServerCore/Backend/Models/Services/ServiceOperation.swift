//
//  ServiceOperation.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The complete set of things the Manager may ask an agent to do to a running service.
///
/// Closed on purpose, unlike most vocabularies in this package. Every case is something the agent
/// knows how to do safely to an allow-listed service, and an unknown value must fail to decode
/// rather than reach the backend. Adding a case is a deliberate, reviewed protocol change.
public enum ServiceOperation: String, Sendable, Hashable, Codable, CaseIterable {

    case start
    case stop
    case restart
}
