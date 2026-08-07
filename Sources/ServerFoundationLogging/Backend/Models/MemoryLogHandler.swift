//
//  MemoryLogHandler.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 02/10/2025.
//

import Foundation
import Logging

/// A `LogHandler` that keeps logs in a ``LogStorage`` ring so they can be streamed live.
///
/// Bootstrapping this is all a Funico server has to do to get a log stream:
///
/// ```swift
/// let storage = LogStorage()
/// LoggingSystem.bootstrap { _ in MemoryLogHandler(storage: storage) }
/// ```
public struct MemoryLogHandler: LogHandler {

    public var metadata = Logger.Metadata()
    public var metadataProvider: Logger.MetadataProvider?
    public var logLevel: Logger.Level = .trace

    public let storage: LogStorage

    /// Also writes each message to stdout.
    ///
    /// On by default because it is what the original did, and because until a managed
    /// server adopts the control channel, stdout is the *only* thing the agent can read
    /// from it.
    public let echoesToStandardOutput: Bool

    public init(
        storage: LogStorage = LogStorage(),
        echoesToStandardOutput: Bool = true,
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        self.storage = storage
        self.echoesToStandardOutput = echoesToStandardOutput
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        if echoesToStandardOutput {
            print(event.message)
        }

        storage.append(
            FNCLog(
                level: event.level,
                message: event.message,
                metadata: resolvedMetadata(for: event),
                source: event.source,
                file: event.file,
                function: event.function,
                line: event.line
            )
        )
    }

    /// Handler metadata, then provider metadata, then the call site — least to most
    /// specific, so a call-site key wins.
    ///
    /// The original dropped handler and provider metadata entirely and forwarded only the
    /// event's, which silently discards anything set with `logger[metadataKey:] =`.
    private func resolvedMetadata(for event: LogEvent) -> Logger.Metadata? {
        var resolved = metadata

        if let provided = metadataProvider?.get() {
            resolved.merge(provided) { _, new in new }
        }
        if let eventMetadata = event.metadata {
            resolved.merge(eventMetadata) { _, new in new }
        }

        return resolved.isEmpty ? nil : resolved
    }
}
