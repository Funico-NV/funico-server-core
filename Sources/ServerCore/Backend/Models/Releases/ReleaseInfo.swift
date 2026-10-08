//
//  ReleaseInfo.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// One GitHub release of a service, as the Manager presents it for deployment.
public struct ReleaseInfo: Sendable, Hashable, Codable, Identifiable {

    /// The repository, as `owner/name`.
    public var repository: String

    /// The git tag — `"v1.6.0"` or `"1.6.0"`, whatever the repository uses.
    public var tag: String

    /// The version the artifact's manifest declares, without a `v` prefix. The value compared
    /// with a running service's reported version after a deployment.
    public var version: String

    /// When the release was published. `nil` for a draft.
    public var publishedAt: Date?

    /// The release notes, as Markdown.
    public var notes: String?

    /// The artifact for the platform this listing was made for, if there is one.
    public var artifact: ReleaseArtifact?

    /// Whether the release may be deployed, and if not, why.
    public var eligibility: ReleaseEligibility

    /// `repository@tag`.
    public var id: String { "\(repository)@\(tag)" }

    /// Creates a release.
    ///
    /// - Parameters:
    ///   - repository: the repository, as `owner/name`.
    ///   - tag: the git tag.
    ///   - version: the version the manifest declares.
    ///   - publishedAt: when the release was published.
    ///   - notes: the release notes, as Markdown.
    ///   - artifact: the artifact for the relevant platform.
    ///   - eligibility: whether the release may be deployed.
    public init(
        repository: String,
        tag: String,
        version: String,
        publishedAt: Date? = nil,
        notes: String? = nil,
        artifact: ReleaseArtifact? = nil,
        eligibility: ReleaseEligibility
    ) {
        self.repository = repository
        self.tag = tag
        self.version = version
        self.publishedAt = publishedAt
        self.notes = notes
        self.artifact = artifact
        self.eligibility = eligibility
    }
}
