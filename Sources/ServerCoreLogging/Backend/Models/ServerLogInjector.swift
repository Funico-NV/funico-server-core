import Logging

/// Connects swift-log to Server Manager through structured stdout and a bounded live buffer.
///
/// Create one instance per service. Inject `logger(label:)` into individual components, or call
/// `bootstrap()` once before creating any loggers (and before creating a Vapor Application).
/// Under systemd, stdout is retained by journald according to the host's retention policy.
/// The in-process `storage` is bounded and does not survive a restart.
public struct ServerLogInjector: Sendable {
    public let storage: LogStorage
    public let minimumLevel: Logger.Level
    public let echoesToStandardOutput: Bool

    public init(
        capacity: Int = LogStorage.defaultCapacity,
        minimumLevel: Logger.Level = .info,
        echoesToStandardOutput: Bool = true
    ) {
        storage = LogStorage(capacity: capacity)
        self.minimumLevel = minimumLevel
        self.echoesToStandardOutput = echoesToStandardOutput
    }

    /// Creates a logger without changing the process-wide logging system.
    public func logger(label: String, metadata: Logger.Metadata = [:]) -> Logger {
        var logger = Logger(label: label) { label in
            handler(label: label, metadataProvider: nil)
        }
        for (key, value) in metadata { logger[metadataKey: key] = value }
        logger[metadataKey: "logger"] = .string(label)
        return logger
    }

    /// Installs the injector for all subsequently created swift-log loggers.
    ///
    /// swift-log permits bootstrap only once per process. Replace an existing logging bootstrap;
    /// do not call this after Vapor's `LoggingSystem.bootstrap(from:)`.
    public func bootstrap() {
        LoggingSystem.bootstrap { label in
            handler(label: label, metadataProvider: LoggingSystem.metadataProvider)
        }
    }

    private func handler(label: String, metadataProvider: Logger.MetadataProvider?) -> MemoryLogHandler {
        var handler = MemoryLogHandler(
            storage: storage,
            echoesToStandardOutput: echoesToStandardOutput,
            metadataProvider: metadataProvider,
            standardOutputFormat: .structured
        )
        handler.logLevel = minimumLevel
        handler[metadataKey: "logger"] = .string(label)
        return handler
    }
}
