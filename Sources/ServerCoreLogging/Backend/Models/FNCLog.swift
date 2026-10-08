//
//  FNCLog.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 03/10/2025.
//

import Foundation
import Logging

/// One structured log record, as it travels from a server to the agent and on to the app.
///
/// Promoted from `funico-invoices-api`, where it was generic but stranded. Every Funico
/// server gets a log stream out of this, not just invoices.
///
/// - Important: the encoded shape is unchanged from `InvoicesAPI.FNCLog`, including the
///   `timestamp` format. `funico-invoices-service` is already emitting these over
///   `WS /log` to a shipped iOS build.
public struct FNCLog: Sendable, Codable {

    public let timestamp: String

    public let level: Logger.Level
    public let message: Logger.Message
    public let metadata: Logger.Metadata?

    public let source: String
    public let file: String
    public let function: String
    public let line: UInt

    /// Records the log as happening *now*.
    ///
    /// Signature-compatible with `InvoicesAPI.FNCLog` so the 1.3.0 typealias shim is a
    /// drop-in.
    public init(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.init(
            date: Date(),
            level: level,
            message: message,
            metadata: metadata,
            source: source,
            file: file,
            function: function,
            line: line
        )
    }

    /// Records the log as happening at a given time.
    ///
    /// The agent needs this: a line recovered from a managed server's stdout, or replayed
    /// after a reconnect, happened when the server wrote it — not when the agent got
    /// around to parsing it.
    public init(
        date: Date,
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.timestamp = FNCLog.timestampFormatter.string(from: date)
        self.level = level
        self.message = message
        self.metadata = metadata
        self.source = source
        self.file = file
        self.function = function
        self.line = line
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.timestamp = try values.decode(String.self, forKey: .timestamp)
        self.level = try values.decode(Logger.Level.self, forKey: .level)
        let messageDescription = try values.decode(String.self, forKey: .message)
        self.message = Logger.Message(stringLiteral: messageDescription)
        self.metadata = try values.decodeIfPresent(Logger.Metadata.self, forKey: .metadata)
        self.source = try values.decode(String.self, forKey: .source)
        self.file = try values.decode(String.self, forKey: .file)
        self.function = try values.decode(String.self, forKey: .function)
        self.line = try values.decode(UInt.self, forKey: .line)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(message.description, forKey: .message)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encode(source, forKey: .source)
        try container.encode(file, forKey: .file)
        try container.encode(function, forKey: .function)
        try container.encode(line, forKey: .line)
    }
}

extension FNCLog {

    public func bytes() throws -> [UInt8] {
        let data = try JSONEncoder().encode(self)
        return [UInt8](data)
    }
}

private extension FNCLog {

    // Not ISO 8601 — this is the existing display format and changing it changes what a
    // shipped iOS build renders in the log list.
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss+SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

fileprivate extension FNCLog {

    enum CodingKeys: String, CodingKey {
        case timestamp
        case level
        case message
        case metadata
        case source
        case file
        case function
        case line
    }
}

/// Makes `Logger.Metadata` encodable, which swift-log does not provide.
///
/// - Warning: this is a retroactive conformance on a type from another module, so exactly
///   one module in a process may declare it. `InvoicesAPI` 1.2.5 declares the same
///   conformance — an app linking both it and this module has a duplicate. That is
///   precisely what `funico-invoices-api` 1.3.0 removes, and until it ships, do not import
///   both into the same target.
extension Logger.MetadataValue: @retroactive Codable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let stringValue):
            try container.encode(CaseType.string, forKey: .type)
            try container.encode(stringValue, forKey: .stringValue)
        case .stringConvertible(let stringConvertibleValue):
            try container.encode(CaseType.stringConvertible, forKey: .type)
            try container.encode(stringConvertibleValue.description, forKey: .stringConvertibleValue)
        case .dictionary(let dictionaryValue):
            try container.encode(CaseType.dictionary, forKey: .type)
            try container.encode(dictionaryValue, forKey: .dictionaryValue)
        case .array(let arrayValue):
            try container.encode(CaseType.array, forKey: .type)
            try container.encode(arrayValue, forKey: .arrayValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CaseType.self, forKey: .type)

        switch type {
        case .string:
            let stringValue = try container.decode(String.self, forKey: .stringValue)
            self = .string(stringValue)
        case .stringConvertible:
            // A `stringConvertible` cannot survive a round trip as itself — only its
            // description was written — so it comes back as a plain string.
            let stringConvertibleValue = try container.decode(String.self, forKey: .stringConvertibleValue)
            self = .stringConvertible(stringConvertibleValue)
        case .dictionary:
            let dictionaryValue = try container.decode(Logger.Metadata.self, forKey: .dictionaryValue)
            self = .dictionary(dictionaryValue)
        case .array:
            let arrayValue = try container.decode([Logger.Metadata.Value].self, forKey: .arrayValue)
            self = .array(arrayValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type

        case stringValue
        case stringConvertibleValue
        case dictionaryValue
        case arrayValue
    }

    private enum CaseType: String, Codable {

        case string
        case stringConvertible
        case dictionary
        case array
    }
}
