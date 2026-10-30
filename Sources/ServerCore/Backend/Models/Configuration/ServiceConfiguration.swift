import Foundation

/// Values accepted for one ephemeral encrypted submission. Never put this type in a command or journal.
public struct ServiceConfigurationPatch: Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Explicit mutations: omitted keys keep their existing values, including secrets.
    public let changes: [Change]
    /// One typed mutation; remove is explicit and an empty text field never means deletion.
    public struct Change: Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
        /// A name approved by the host's configuration policy.
        public let name: String
        /// The only permitted mutations.
        public enum Action: String, Sendable, Codable { case set, remove }
        /// Set or remove; neither can execute a process.
        public let action: Action
        /// Only set carries a value. This must remain write-only throughout the control plane.
        public let value: String?
        /// Creates one explicit mutation; validation happens before encryption and again on the host.
        public init(name: String, action: Action, value: String? = nil) { self.name = name; self.action = action; self.value = value }
        /// Individual mutations are redacted too, even when logged separately from their patch.
        public var description: String { "ServiceConfigurationChange(<redacted>)" }
        /// Debug output never expands the write-only value.
        public var debugDescription: String { description }
    }
    /// Creates an in-memory patch; never persist this plaintext value.
    public init(changes: [Change]) { self.changes = changes }
    /// Checks structural bounds without echoing input. Host policy performs type/requiredness validation.
    public func validate() throws {
        guard (1...64).contains(changes.count), Set(changes.map(\.name)).count == changes.count else { throw Self.invalid() }
        for change in changes {
            guard (try? ServiceEnvironmentDefinition(name: change.name, title: change.name, type: .string, required: false, secret: true)) != nil,
                  (change.action == .set) == (change.value != nil),
                  change.value.map({ $0.utf8.count <= 4096 && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0.value != 0xfeff && !(0xfdd0...0xfdef).contains($0.value) && ($0.value & 0xffff) < 0xfffe } }) ?? true else { throw Self.invalid() }
        }
        guard try JSONEncoder().encode(self).count <= 32_768 else { throw Self.invalid() }
    }
    /// Deliberately redacts even non-secret values; their classification is authoritative only on the host.
    public var description: String { "ServiceConfigurationPatch(<redacted>)" }
    /// Debug logging must not reveal submitted values either.
    public var debugDescription: String { description }
    private static func invalid() -> ServerCoreError { .init(.invalidRequest, "Invalid service configuration changes.") }
}

/// Authenticated context for a configuration envelope; never contains values or paths.
public struct ConfigurationEnvelopeContext: Sendable, Hashable, Codable {
    /// Caller operation UUID; the Agent additionally requires it to equal the command UUID.
    public let operation: String
    /// Enrolled host binding, preventing delivery to another host.
    public let server: ServerID
    /// Host-approved service binding.
    public let service: ServiceID
    /// Opaque keyed version of the current file and policy, not a public hash of secret values.
    public let revision: String
    /// Process-scoped encryption key identity. An Agent restart invalidates old submissions.
    public let keyID: String
    /// Bounded validity in Unix seconds; old encrypted patches are not offline work orders.
    public let expiresAt: Int64
    /// Creates an authenticated binding. Validate on both sides of the channel.
    public init(operation: String, server: ServerID, service: ServiceID, revision: String, keyID: String, expiresAt: Int64) {
        self.operation = operation; self.server = server; self.service = service; self.revision = revision; self.keyID = keyID; self.expiresAt = expiresAt
    }
    /// Canonical authenticated bytes independent of process-wide JSON encoder settings.
    public func authenticatedBytes() throws -> Data {
        guard let id = UUID(uuidString: operation), operation == id.uuidString.lowercased(),
              UUID(uuidString: keyID) != nil, revision.utf8.count == 64,
              revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              [server.rawValue, service.rawValue].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) } }) else {
            throw ServerCoreError(.invalidRequest, "Invalid configuration envelope context.")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// RFC 9180 HPKE ciphertext. Only this encrypted representation may enter command journals.
public struct SealedServiceConfiguration: Sendable, Hashable, Codable {
    /// Authenticated routing/revision/expiry data.
    public let context: ConfigurationEnvelopeContext
    /// HPKE X25519 encapsulated key, base64-encoded; never a private key.
    public let encapsulatedKey: String
    /// HPKE ciphertext including its authentication tag, base64-encoded.
    public let ciphertext: String
    /// Creates the wire envelope produced by the crypto product.
    public init(context: ConfigurationEnvelopeContext, encapsulatedKey: String, ciphertext: String) {
        self.context = context; self.encapsulatedKey = encapsulatedKey; self.ciphertext = ciphertext
    }
}

/// Read-only setting names/classification/presence. No current values or defaults are returned.
public struct ServiceConfigurationSnapshot: Sendable, Hashable, Codable {
    /// One host-approved field. All fields are write-only in this first implementation.
    public struct Field: Sendable, Hashable, Codable {
        /// Approved variable name.
        public let name: String
        /// Human-readable setting name from the protected policy.
        public let title: String
        /// Type enforced by the host on write.
        public let type: ServiceEnvironmentDefinition.ValueType
        /// Whether removal/empty input must be refused.
        public let required: Bool
        /// Secret classification; current values are omitted for every classification.
        public let secret: Bool
        /// Whether an explicit value exists, without reading it back to a client.
        public let isSet: Bool
        /// Creates public metadata from protected policy, without including a default value.
        public init(definition: ServiceEnvironmentDefinition, isSet: Bool) {
            name = definition.name; title = definition.title; type = definition.type; required = definition.required; secret = definition.secret; self.isSet = isSet
        }
    }
    /// Host-approved service.
    public let service: ServiceID
    /// Opaque process-bound optimistic concurrency token.
    public let revision: String
    /// Public X25519 HPKE recipient key, never a signing key or private key.
    public let recipientKey: String
    /// Agent-process identity for the recipient key.
    public let keyID: String
    /// Latest accepted envelope expiry, in Unix seconds.
    public let expiresAt: Int64
    /// Whether this host/backend/file has been explicitly prepared for writes.
    public let writable: Bool
    /// Fixed reason for a missing bootstrap prerequisite; no host file contents.
    public let reason: String?
    /// UUID stamped atomically with the current values; identifies a completed save after a lost response.
    public let lastOperationID: String?
    /// Approved fields and their presence only.
    public let fields: [Field]
    /// Creates a host snapshot. Remote clients cannot provide facts through this response.
    public init(service: ServiceID, revision: String, recipientKey: String, keyID: String, expiresAt: Int64, writable: Bool, reason: String?, fields: [Field], lastOperationID: String? = nil) {
        self.service = service; self.revision = revision; self.recipientKey = recipientKey; self.keyID = keyID; self.expiresAt = expiresAt
        self.writable = writable; self.reason = reason; self.fields = fields; self.lastOperationID = lastOperationID
    }
}

/// Saving never implicitly restarts a service; its running process may still use the previous environment.
public struct ServiceConfigurationReceipt: Sendable, Hashable, Codable {
    /// Target service and opaque new revision, safe to persist in operation results.
    public let service: ServiceID
    /// New host configuration version; no public digest of secret values.
    public let revision: String
    /// Names only, suitable for auditing.
    public let changedNames: [String]
    /// Explicit reminder that a separate confirmed restart/install is required.
    public let restartRequired: Bool
    /// Creates a saved, not-applied receipt.
    public init(service: ServiceID, revision: String, changedNames: [String], restartRequired: Bool = true) {
        self.service = service; self.revision = revision; self.changedNames = changedNames; self.restartRequired = restartRequired
    }
}
