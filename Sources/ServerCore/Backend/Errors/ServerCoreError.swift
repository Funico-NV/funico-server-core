//
//  ServerCoreError.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// An error that crosses a process boundary: from the agent to the Manager, and from the Manager
/// to the app or the web console.
///
/// It carries a stable machine-readable ``code`` and a human-readable ``message``. Clients switch
/// on the code and localise from it; the message is for logs and for the operator who reads them,
/// and is never parsed. That split is why this is a struct and not an enum with associated values:
/// a Swift enum does not survive a trip through JSON to a browser.
///
/// ```swift
/// do {
///     try await backend.perform(.restart, on: "invoices")
/// } catch let error as ServerCoreError where error.code == .unknownService {
///     // The host does not list this service.
/// }
/// ```
public struct ServerCoreError: Error, Sendable, Hashable, Codable {

    /// What went wrong, as a stable identifier.
    ///
    /// Open rather than a closed enum, so a newer agent can report a code an older app has never
    /// heard of without failing to decode; the app shows ``ServerCoreError/message`` instead.
    public struct Code: StringBackedValue {

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// The service is not in the host's allow-list. Also returned for a service that exists on
        /// the host but is not listed, so the answer does not reveal what else runs there.
        public static let unknownService = Code("unknownService")

        /// The command or operation is not one this agent supports.
        public static let unsupportedCommand = Code("unsupportedCommand")

        /// The request is malformed: a missing field, a value out of range.
        public static let invalidRequest = Code("invalidRequest")

        /// Another command or deployment for the same service is in progress. Commands are
        /// serialised per service, so the caller should wait for that one to finish.
        public static let busy = Code("busy")

        /// The command's deadline passed before the agent could start it. It was not run.
        public static let deadlineExceeded = Code("deadlineExceeded")

        /// The command was cancelled before it ran, or a deployment before activation.
        public static let cancelled = Code("cancelled")

        /// An artifact's manifest is malformed or does not match the service, platform or agent
        /// version. See ``ArtifactManifest/validate()``.
        public static let invalidManifest = Code("invalidManifest")

        /// An artifact's checksum or signature did not verify. Nothing was installed.
        public static let verificationFailed = Code("verificationFailed")

        /// The service manager itself (systemd, the process supervisor) refused or failed.
        public static let backendFailure = Code("backendFailure")

        /// The service did not become ready after a start, restart or activation.
        public static let notReady = Code("notReady")

        /// The thing asked for does not exist: a release, a deployment, a log cursor.
        public static let notFound = Code("notFound")
    }

    /// What went wrong. Switch on this.
    public let code: Code

    /// What went wrong, for a person reading a log. Not localised and not stable.
    public let message: String

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - code: the stable identifier clients switch on.
    ///   - message: detail for a person reading a log.
    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }
}

extension ServerCoreError: CustomStringConvertible {

    public var description: String { "\(code): \(message)" }
}
