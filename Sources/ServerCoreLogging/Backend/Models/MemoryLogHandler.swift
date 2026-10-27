//
//  MemoryLogHandler.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 02/10/2025.
//

import Foundation
import Logging
import ServerCore

/// A `LogHandler` that keeps logs in a ``LogStorage`` ring so they can be streamed live.
///
/// Bootstrapping this is all a Funico server has to do to get a log stream:
///
/// ```swift
/// let storage = LogStorage()
/// LoggingSystem.bootstrap { _ in MemoryLogHandler(storage: storage) }
/// ```
public struct MemoryLogHandler: LogHandler {

    public enum StandardOutputFormat: Sendable {
        case plain
        /// One JSON record per line, prefixed with a syslog priority for journald.
        case structured
    }

    public let standardOutputFormat: StandardOutputFormat

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
        metadataProvider: Logger.MetadataProvider? = nil,
        standardOutputFormat: StandardOutputFormat = .plain
    ) {
        self.standardOutputFormat = standardOutputFormat
        self.storage = storage
        self.echoesToStandardOutput = echoesToStandardOutput
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        let record = FNCLog(
            level: event.level,
            message: event.message,
            metadata: resolvedMetadata(for: event),
            source: event.source,
            file: event.file,
            function: event.function,
            line: event.line
        )
        storage.append(record)

        if echoesToStandardOutput {
            switch standardOutputFormat {
            case .plain:
                print(event.message)
            case .structured:
                // JSON escapes embedded newlines, keeping each event on a single journal line.
                if let line = try? Self.structuredLine(record) {
                    Self.writeLine(line)
                }
            }
        }
    }

    static func structuredLine(_ record: FNCLog) throws -> String {
        let data = try JSONEncoder().encode(record)
        return "<\(LogPriority(record.level).syslogLevel)>FNC_LOG:" + String(decoding: data, as: UTF8.self)
    }

    private static let outputLock = NSLock()

    private static func writeLine(_ line: String) {
        outputLock.lock()
        defer { outputLock.unlock() }
        // Avoid stdio buffering: a quiet service must make its latest log visible immediately.
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
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
