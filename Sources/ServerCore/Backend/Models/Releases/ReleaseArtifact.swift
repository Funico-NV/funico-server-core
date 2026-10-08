//
//  ReleaseArtifact.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// The three release assets that make one deployable build: the archive, its checksum and its
/// signature.
///
/// A release without all three for the host's platform is not deployable — see
/// ``ReleaseEligibility``. The agent downloads all three and verifies the archive itself; it does
/// not trust the Manager's word that a build is genuine.
public struct ReleaseArtifact: Sendable, Hashable, Codable {

    /// The platform this build runs on.
    public var platform: ArtifactPlatform

    /// The `.tar.gz` holding `manifest.json`, `bin/` and `lib/`.
    public var archiveURL: URL

    /// The `.sha256` file: the archive's SHA-256, hex-encoded.
    public var checksumURL: URL

    /// The `.sig` file: an Ed25519 signature over the archive, made with the key held in the
    /// repository's GitHub Actions secrets. The agent checks it against the public key pinned for
    /// the service in its allow-list.
    public var signatureURL: URL

    /// The archive's size, for progress and a disk-space check before downloading.
    public var size: Int64?

    /// Creates an artifact reference.
    ///
    /// - Parameters:
    ///   - platform: the platform this build runs on.
    ///   - archiveURL: the `.tar.gz` asset.
    ///   - checksumURL: the `.sha256` asset.
    ///   - signatureURL: the `.sig` asset.
    ///   - size: the archive's size in bytes, if known.
    public init(
        platform: ArtifactPlatform,
        archiveURL: URL,
        checksumURL: URL,
        signatureURL: URL,
        size: Int64? = nil
    ) {
        self.platform = platform
        self.archiveURL = archiveURL
        self.checksumURL = checksumURL
        self.signatureURL = signatureURL
        self.size = size
    }
}
