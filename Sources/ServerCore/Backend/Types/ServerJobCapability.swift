//
//  ServerJobCapability.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// A control a server says it supports for a job.
///
/// Reported per job, at runtime, so the app renders the buttons a server actually has
/// instead of the hardcoded capability checks currently baked into `InvoicesServerView`.
/// Open for the same reason as ``ServerJob``: a new managed server must not require a new
/// app build.
public struct ServerJobCapability: Sendable, Hashable, RawRepresentable, Identifiable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var id: String { rawValue }
}

extension ServerJobCapability {

    public static let start = ServerJobCapability("start")
    public static let stop = ServerJobCapability("stop")
    public static let pause = ServerJobCapability("pause")
    public static let resume = ServerJobCapability("resume")
    public static let execute = ServerJobCapability("execute")
}

extension ServerJobCapability: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ServerJobCapability: CustomStringConvertible {

    public var description: String { rawValue }
}
