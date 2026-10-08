//
//  ArtifactPlatform.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The operating system and CPU architecture a compiled artifact runs on.
///
/// Spelled the way the release asset names spell it — `invoices-1.6.0-linux-x86_64.tar.gz` — so a
/// platform can be matched against an asset name without a translation table.
public struct ArtifactPlatform: Sendable, Hashable, Codable, CustomStringConvertible {

    /// `"linux"` or `"macos"`.
    public var os: String

    /// `"x86_64"` or `"aarch64"`, as `uname -m` reports it.
    public var arch: String

    /// Creates a platform.
    ///
    /// - Parameters:
    ///   - os: `"linux"` or `"macos"`.
    ///   - arch: the CPU architecture as `uname -m` reports it.
    public init(os: String, arch: String) {
        self.os = os
        self.arch = arch
    }

    /// 64-bit Intel and AMD Linux — every Funico host today.
    public static let linuxX86_64 = ArtifactPlatform(os: "linux", arch: "x86_64")

    /// 64-bit ARM Linux.
    public static let linuxAArch64 = ArtifactPlatform(os: "linux", arch: "aarch64")

    /// `os-arch`, as it appears in an asset name.
    public var description: String { "\(os)-\(arch)" }
}
