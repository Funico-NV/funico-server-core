//
//  ServerResources.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// A sample of a host's load, taken by a ``ResourceSampler``.
///
/// Sizes are bytes, so no client has to guess whether a number is KiB or MB.
public struct ServerResources: Sendable, Hashable, Codable {

    /// When the sample was taken. Samples are periodic; a stale one means the agent is not
    /// reporting.
    public var sampledAt: Date

    /// CPU in use across all cores, from `0` (idle) to `1` (every core busy).
    public var cpuUsage: Double

    /// Memory in use, excluding page cache the kernel can reclaim.
    public var memoryUsedBytes: UInt64

    /// Physical memory.
    public var memoryTotalBytes: UInt64

    /// Space used on the filesystem holding the releases.
    public var diskUsedBytes: UInt64

    /// Size of the filesystem holding the releases. That one rather than `/` because it is the one
    /// a deployment fills.
    public var diskTotalBytes: UInt64

    /// The 1, 5 and 15-minute load averages.
    public var loadAverage: [Double]

    /// Time since the host booted.
    public var uptime: TimeInterval

    /// Creates a sample.
    ///
    /// - Parameters:
    ///   - sampledAt: when the sample was taken.
    ///   - cpuUsage: CPU in use, `0...1`.
    ///   - memoryUsedBytes: memory in use.
    ///   - memoryTotalBytes: physical memory.
    ///   - diskUsedBytes: space used where releases live.
    ///   - diskTotalBytes: size of the filesystem where releases live.
    ///   - loadAverage: the 1, 5 and 15-minute load averages.
    ///   - uptime: time since boot.
    public init(
        sampledAt: Date,
        cpuUsage: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        diskUsedBytes: UInt64,
        diskTotalBytes: UInt64,
        loadAverage: [Double],
        uptime: TimeInterval
    ) {
        self.sampledAt = sampledAt
        self.cpuUsage = cpuUsage
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.loadAverage = loadAverage
        self.uptime = uptime
    }
}
