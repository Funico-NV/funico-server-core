//
//  ResourceSampler.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// Measures a host's load — `/proc` on Linux, `host_statistics` on macOS.
public protocol ResourceSampler: Sendable {

    /// One sample, taken now.
    ///
    /// CPU usage is a rate, so an implementation compares against its previous call; the first
    /// sample may report `0` for it.
    func sample() async throws -> ServerResources
}
