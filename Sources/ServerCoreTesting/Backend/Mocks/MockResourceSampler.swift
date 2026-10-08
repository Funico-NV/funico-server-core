//
//  MockResourceSampler.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// A `ResourceSampler` that returns a fixed sample, re-dated to the moment it is taken.
public struct MockResourceSampler: ResourceSampler {

    /// The sample returned, apart from its date.
    public var resources: ServerResources

    /// Creates a sampler. The default describes a quiet 8 GB host with a 100 GB disk.
    ///
    /// - Parameter resources: the sample to return.
    public init(resources: ServerResources = ServerResources(
        sampledAt: Date(),
        cpuUsage: 0.1,
        memoryUsedBytes: 2 << 30,
        memoryTotalBytes: 8 << 30,
        diskUsedBytes: 20 << 30,
        diskTotalBytes: 100 << 30,
        loadAverage: [0.2, 0.15, 0.1],
        uptime: 86_400
    )) {
        self.resources = resources
    }

    public func sample() async throws -> ServerResources {
        var sample = resources
        sample.sampledAt = Date()
        return sample
    }
}
