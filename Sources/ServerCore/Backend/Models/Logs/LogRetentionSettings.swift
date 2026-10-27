import Foundation

/// Complete per-service retention policy in days. Zero disables storage for that severity.
/// Administrators may update this through Manager; the host allow-list is unaffected.
public struct LogRetentionSettings: Sendable, Hashable, Codable {
    public let retentionDays: [String: Double]

    public static let defaults: [String: Double] = [
        "debug": 1, "info": 7, "notice": 14, "warning": 30,
        "error": 90, "critical": 180, "alert": 180, "emergency": 180
    ]

    /// Validates a complete policy, rejecting unknown/missing levels and invalid durations.
    public init(retentionDays: [String: Double] = LogRetentionSettings.defaults) throws {
        guard Set(retentionDays.keys) == Set(Self.defaults.keys),
              retentionDays.values.allSatisfy({ $0.isFinite && (0...3650).contains($0) }) else {
            throw ServerCoreError(.invalidRequest, "Provide all eight log priorities with retention of 0…3650 days")
        }
        self.retentionDays = retentionDays
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(retentionDays: values.decode([String: Double].self, forKey: .retentionDays))
    }

    private enum CodingKeys: String, CodingKey { case retentionDays }
}

/// Agent-side boundary for reading and changing durable per-service log retention.
public protocol LogRetentionManaging: Sendable {
    func retention(for service: ServiceID) async throws -> LogRetentionSettings
    func setRetention(_ settings: LogRetentionSettings, for service: ServiceID) async throws -> LogRetentionSettings
}
