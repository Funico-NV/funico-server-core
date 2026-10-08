//
//  MockReleaseSource.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation
import ServerCore

/// A `ReleaseSource` over a fixed list per repository.
///
/// Returns the releases as given, whatever platform is asked for: eligibility is part of the
/// fixture, so a test states exactly which releases it expects to be deployable.
public struct MockReleaseSource: ReleaseSource {

    /// The releases of each repository, newest first.
    public var releases: [String: [ReleaseInfo]]

    /// Creates a source.
    ///
    /// - Parameter releases: the releases of each repository, keyed by `owner/name`, newest first.
    public init(releases: [String: [ReleaseInfo]]) {
        self.releases = releases
    }

    public func releases(of repository: String, for platform: ArtifactPlatform) async throws -> [ReleaseInfo] {
        releases[repository] ?? []
    }
}
