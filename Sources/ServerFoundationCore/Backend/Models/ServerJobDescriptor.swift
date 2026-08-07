//
//  ServerJobDescriptor.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// A server's runtime description of one of its jobs.
///
/// This is what replaces `InvoiceJob.allCases` in the app's job picker. A compiled-in
/// `allCases` means the app can only ever show the jobs it was built knowing about, which
/// is the thing that makes "N servers" impossible. Served from
/// `GET /v1/servers/{id}/jobs`, the list is whatever the server says it is.
public struct ServerJobDescriptor: Sendable, Hashable, Codable, Identifiable {

    public let job: ServerJob

    /// Display name. Comes from the server so the app does not need a localisation entry
    /// per job of a server it has never heard of.
    public let title: String

    /// Whether the server starts this job by itself when it comes up.
    public let autoStart: Bool

    /// Which controls to offer. Empty means the job is observable but not controllable.
    public let capabilities: Set<ServerJobCapability>

    public var id: String { job.rawValue }

    public init(
        job: ServerJob,
        title: String,
        autoStart: Bool = false,
        capabilities: Set<ServerJobCapability> = []
    ) {
        self.job = job
        self.title = title
        self.autoStart = autoStart
        self.capabilities = capabilities
    }

    public func supports(_ capability: ServerJobCapability) -> Bool {
        capabilities.contains(capability)
    }
}
