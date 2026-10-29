import Foundation

/// The versioned `funico-service.json` shipped inside a signed release.
///
/// This describes application intent, not host authority. A host administrator must approve
/// the named profile; only the Agent determines accounts, installation roots and supervisor
/// permissions. A default-branch copy may be used for discovery, never as installation authority.
public struct ServiceDefinition: Sendable, Hashable, Codable {
    /// The only understood format. Unsupported versions fail closed.
    public static let currentSchema = 1
    /// The file hashed in `ArtifactManifest.files` and verified with the rest of the release.
    public static let filename = "funico-service.json"
    /// Bounds untrusted repository metadata before JSON decoding.
    public static let maximumBytes = 65_536

    /// The definition version; it is independent of the artifact manifest version.
    public let schema: Int
    /// Stable service slug, never a unit name or host path.
    public let service: ServiceID
    /// Human-facing name, rendered as text by clients.
    public let displayName: String
    /// Requested host-approved policy profile. This cannot grant capabilities by itself.
    public let profile: String
    /// Executable/argument declarations per OS and architecture, without shell interpretation.
    public let platforms: [ServiceRuntimeDefinition]
    /// Names, types and presentation metadata; secret values never belong in this file.
    public let environment: [ServiceEnvironmentDefinition]
    /// Must agree with the artifact migration flag; confirmation remains a separate authorization.
    public let requiresMigration: Bool
    /// Optional loopback readiness probe; it cannot name a remote host.
    public let readiness: ServiceReadinessDefinition?

    /// Creates and validates application intent; no files are written or processes started.
    public init(schema: Int = currentSchema, service: ServiceID, displayName: String, profile: String,
                platforms: [ServiceRuntimeDefinition], environment: [ServiceEnvironmentDefinition] = [],
                readiness: ServiceReadinessDefinition? = nil, requiresMigration: Bool = false) throws {
        guard schema == Self.currentSchema, DefinitionValidation.slug(service.rawValue),
              DefinitionValidation.text(displayName, maximum: 128), !displayName.trimmingCharacters(in: .whitespaces).isEmpty,
              DefinitionValidation.slug(profile), !platforms.isEmpty, platforms.count <= 8,
              Set(platforms.map(\.platform)).count == platforms.count,
              environment.count <= 64, Set(environment.map(\.name)).count == environment.count else {
            throw DefinitionValidation.invalid("The service definition has an unsupported version, invalid identity, or duplicate/oversized declarations.")
        }
        self.schema = schema; self.service = service; self.displayName = displayName; self.profile = profile
        self.platforms = platforms; self.environment = environment; self.readiness = readiness
        self.requiresMigration = requiresMigration
        guard try JSONEncoder().encode(self).count <= Self.maximumBytes else {
            throw DefinitionValidation.invalid("The encoded service definition exceeds its size limit.")
        }
    }

    /// Decodes a bounded document and rejects unknown fields, malformed types and unsupported versions.
    /// Errors do not echo metadata values, since a mistakenly supplied value could be a credential.
    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw DefinitionValidation.invalid("The service definition is empty or exceeds its size limit.")
        }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch let error as ServerCoreError { throw error }
        catch { throw DefinitionValidation.invalid("The service definition is malformed or uses an unsupported value or field.") }
    }

    /// Finds intent for an artifact platform. `nil` must be shown as unsupported, never approximated.
    public func runtime(for platform: ArtifactPlatform) -> ServiceRuntimeDefinition? {
        platforms.first { $0.platform == platform }
    }

    /// Checks agreement with an artifact manifest after signature, archive and file-hash verification.
    /// This method performs no cryptography. The caller must load these bytes from the verified tree,
    /// not from a mutable repository branch. Required configuration names must agree exactly.
    public func validate(for manifest: ArtifactManifest) throws {
        do { try manifest.validate() }
        catch { throw DefinitionValidation.invalid("The artifact manifest is invalid.") }
        guard manifest.service == service, manifest.files[Self.filename] != nil, manifest.requiresMigration == requiresMigration,
              let runtime = runtime(for: manifest.platform), runtime.executable == manifest.entrypoint,
              Set(manifest.configKeys).count == manifest.configKeys.count,
              Set(manifest.configKeys) == Set(environment.filter(\.required).map(\.name)) else {
            throw DefinitionValidation.invalid("The service definition does not agree with the artifact service, files, platform, entrypoint or required settings.")
        }
        if manifest.healthPath != readiness?.path {
            throw DefinitionValidation.invalid("The service definition and artifact disagree about readiness.")
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, service, displayName, profile, platforms, environment, readiness, requiresMigration
    }
    /// Decodes a schema-1 object with the same validation as the public initializer; unknown fields fail closed.
    public init(from decoder: any Decoder) throws {
        try DefinitionValidation.rejectUnknown(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(schema: values.decode(Int.self, forKey: .schema), service: values.decode(ServiceID.self, forKey: .service),
            displayName: values.decode(String.self, forKey: .displayName), profile: values.decode(String.self, forKey: .profile),
            platforms: values.decode([ServiceRuntimeDefinition].self, forKey: .platforms),
            environment: values.contains(.environment) ? values.decode([ServiceEnvironmentDefinition].self, forKey: .environment) : [],
            readiness: values.contains(.readiness) ? values.decode(ServiceReadinessDefinition.self, forKey: .readiness) : nil,
            requiresMigration: values.contains(.requiresMigration) ? values.decode(Bool.self, forKey: .requiresMigration) : false)
    }
}

/// An executable inside a verified release, with literal argv entries rather than a command string.
public struct ServiceRuntimeDefinition: Sendable, Hashable, Codable {
    /// OS names are deliberately closed in schema 1; support requires an actual Agent backend.
    public enum OperatingSystem: String, Sendable, Codable {
        /// A host with an explicitly approved Linux supervisor backend.
        case linux
        /// A host with an explicitly approved macOS supervisor backend.
        case macos
    }
    /// Canonical artifact architecture names; macOS ARM builds use `aarch64` here as well.
    public enum Architecture: String, Sendable, Codable {
        /// 64-bit Intel/AMD artifact spelling.
        case x86_64
        /// 64-bit ARM artifact spelling, including Apple silicon.
        case aarch64
    }
    /// Intended supervisor platform, not a request to run a platform-specific shell.
    public let os: OperatingSystem
    /// Must match the selected host and artifact exactly.
    public let arch: Architecture
    /// Portable ASCII path inside the release. Absolute paths and traversal are forbidden.
    public let executable: String
    /// Arguments are literal, bounded strings. Shell substitutions and environment expansion are not performed.
    public let arguments: [String]
    /// Identity used to match release artifacts without OS-name translation.
    public var platform: ArtifactPlatform { .init(os: os.rawValue, arch: arch.rawValue) }

    /// Validates an executable declaration independently of host policy or artifact availability.
    public init(os: OperatingSystem, arch: Architecture, executable: String, arguments: [String] = []) throws {
        guard DefinitionValidation.executable(executable), arguments.count <= 32,
              arguments.allSatisfy({ DefinitionValidation.text($0, maximum: 2_048, empty: true) }),
              arguments.reduce(0, { $0 + $1.utf8.count }) <= 8_192 else {
            throw DefinitionValidation.invalid("The service executable path or literal arguments are invalid or exceed their limits.")
        }
        self.os = os; self.arch = arch; self.executable = executable; self.arguments = arguments
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case os, arch, executable, arguments }
    /// Decodes a schema-1 object with the same validation as the public initializer; unknown fields fail closed.
    public init(from decoder: any Decoder) throws {
        try DefinitionValidation.rejectUnknown(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(os: values.decode(OperatingSystem.self, forKey: .os), arch: values.decode(Architecture.self, forKey: .arch),
            executable: values.decode(String.self, forKey: .executable),
            arguments: values.contains(.arguments) ? values.decode([String].self, forKey: .arguments) : [])
    }
}

/// Schema for a service environment variable. Values are supplied separately through configuration APIs.
public struct ServiceEnvironmentDefinition: Sendable, Hashable, Codable {
    /// Textual process-environment types. Defaults and runtime values use strings, including numbers.
    public enum ValueType: String, Sendable, Codable {
        /// Text is passed literally, never expanded as a shell expression.
        case string
        /// A canonical signed 64-bit integer represented as text in the process environment.
        case integer
        /// Exactly `true` or `false`, without locale-dependent coercion.
        case boolean
        /// An HTTP(S) endpoint without embedded credentials. Database URLs use secret string fields.
        case url
    }
    /// Portable uppercase name. Runtime injection and supervisor-control variables are refused.
    public let name: String
    /// Human-facing label, never interpreted as markup.
    public let title: String
    /// Explains what the operator needs to provide without embedding an actual secret.
    public let help: String?
    /// Validation applied before a value reaches the host backend.
    public let type: ValueType
    /// A required key must also appear in the matching artifact's `configKeys`.
    public let required: Bool
    /// Secret fields must be write-only in configuration interfaces. There can be no secret default.
    public let secret: Bool
    /// Non-secret textual default. It never overrides a host's existing configured value.
    public let defaultValue: String?
    /// Optional finite vocabulary, supported only for string values.
    public let choices: [String]?
    /// Inclusive bound, supported only for integers.
    public let minimum: Int64?
    /// Inclusive bound, supported only for integers.
    public let maximum: Int64?

    /// Creates and validates a setting schema. Secret classification and requiredness are explicit.
    public init(name: String, title: String, help: String? = nil, type: ValueType, required: Bool, secret: Bool,
                defaultValue: String? = nil, choices: [String]? = nil, minimum: Int64? = nil, maximum: Int64? = nil) throws {
        guard DefinitionValidation.environmentName(name), DefinitionValidation.text(title, maximum: 128),
              help.map({ DefinitionValidation.text($0, maximum: 2_000, empty: true) }) ?? true,
              !secret || defaultValue == nil,
              (minimum == nil && maximum == nil) || type == .integer,
              minimum.map({ (-9_007_199_254_740_991...9_007_199_254_740_991).contains($0) }) ?? true,
              maximum.map({ (-9_007_199_254_740_991...9_007_199_254_740_991).contains($0) }) ?? true,
              minimum == nil || maximum == nil || minimum! <= maximum!,
              choices == nil || (type == .string && choices!.count > 0 && choices!.count <= 100 &&
                Set(choices!).count == choices!.count && choices!.allSatisfy { DefinitionValidation.text($0, maximum: 256, empty: true) }) else {
            throw DefinitionValidation.invalid("The environment schema contains an invalid/reserved name, unsupported constraint or secret default.")
        }
        self.name = name; self.title = title; self.help = help; self.type = type; self.required = required; self.secret = secret
        self.defaultValue = defaultValue; self.choices = choices; self.minimum = minimum; self.maximum = maximum
        if let defaultValue { try validateValue(defaultValue) }
    }

    /// Validates a supplied string without echoing it in an error. Does not store or log the value.
    /// An absent optional value is represented by absence, not by this function accepting invalid text.
    public func validateValue(_ value: String) throws {
        guard DefinitionValidation.text(value, maximum: 8_192, empty: !required),
              choices.map({ $0.contains(value) }) ?? true else {
            throw DefinitionValidation.invalid("An environment value violates its text or choice constraints.")
        }
        switch type {
        case .string: break
        case .integer:
            guard let number = Int64(value), value == String(number),
                  minimum.map({ number >= $0 }) ?? true, maximum.map({ number <= $0 }) ?? true else {
                throw DefinitionValidation.invalid("An environment value is not a canonical integer within its bounds.")
            }
        case .boolean:
            guard value == "true" || value == "false" else { throw DefinitionValidation.invalid("An environment value must be true or false.") }
        case .url:
            guard let url = URLComponents(string: value), url.scheme == "https" || url.scheme == "http",
                  url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil,
                  url.port.map({ (1...65_535).contains($0) }) ?? true,
                  !value.contains(" "), !value.contains("\\") else {
                throw DefinitionValidation.invalid("An environment URL must be an HTTP(S) endpoint without credentials or a fragment.")
            }
        }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, title, help, type, required, secret, defaultValue, choices, minimum, maximum
    }
    /// Decodes a schema-1 object with the same validation as the public initializer; unknown fields fail closed.
    public init(from decoder: any Decoder) throws {
        try DefinitionValidation.rejectUnknown(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: values.decode(String.self, forKey: .name), title: values.decode(String.self, forKey: .title),
            help: values.contains(.help) ? values.decode(String.self, forKey: .help) : nil,
            type: values.decode(ValueType.self, forKey: .type), required: values.decode(Bool.self, forKey: .required),
            secret: values.decode(Bool.self, forKey: .secret),
            defaultValue: values.contains(.defaultValue) ? values.decode(String.self, forKey: .defaultValue) : nil,
            choices: values.contains(.choices) ? values.decode([String].self, forKey: .choices) : nil,
            minimum: values.contains(.minimum) ? values.decode(Int64.self, forKey: .minimum) : nil,
            maximum: values.contains(.maximum) ? values.decode(Int64.self, forKey: .maximum) : nil)
    }
}

/// A readiness GET on host loopback. It cannot nominate a URL, credentials, query or remote network target.
public struct ServiceReadinessDefinition: Sendable, Hashable, Codable {
    /// Non-privileged local listener requested by the application; host policy must also approve it.
    public let port: Int
    /// Simple absolute HTTP path, without dot segments or encoded characters.
    public let path: String
    /// Upper bound for startup readiness. A host can impose a stricter limit.
    public let timeoutSeconds: Int
    /// Time the supervisor must remain stable; this cannot exceed the readiness timeout.
    public let stableSeconds: Int

    /// Describes a bounded readiness probe. The backend always supplies the loopback host itself.
    public init(port: Int, path: String, timeoutSeconds: Int = 60, stableSeconds: Int = 10) throws {
        guard (1_024...65_535).contains(port), DefinitionValidation.healthPath(path),
              (1...300).contains(timeoutSeconds), (1...60).contains(stableSeconds), stableSeconds <= timeoutSeconds else {
            throw DefinitionValidation.invalid("The readiness port, path or time bounds are invalid.")
        }
        self.port = port; self.path = path; self.timeoutSeconds = timeoutSeconds; self.stableSeconds = stableSeconds
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case port, path, timeoutSeconds, stableSeconds }
    /// Decodes a schema-1 object with the same validation as the public initializer; unknown fields fail closed.
    public init(from decoder: any Decoder) throws {
        try DefinitionValidation.rejectUnknown(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(port: values.decode(Int.self, forKey: .port), path: values.decode(String.self, forKey: .path),
            timeoutSeconds: values.contains(.timeoutSeconds) ? values.decode(Int.self, forKey: .timeoutSeconds) : 60,
            stableSeconds: values.contains(.stableSeconds) ? values.decode(Int.self, forKey: .stableSeconds) : 10)
    }
}

/// Decoder/grammar internals shared by each strictly versioned object above.
private enum DefinitionValidation {
    static func invalid(_ text: String) -> ServerCoreError { .init(.invalidManifest, text) }
    static func slug(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64, value.first?.isASCII == true,
              value.first?.isLetter == true || value.first?.isNumber == true, !value.contains("..") else { return false }
        return value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }
    }
    static func text(_ value: String, maximum: Int, empty: Bool = false) -> Bool {
        (empty || !value.isEmpty) && value.utf8.count <= maximum &&
        value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    static func executable(_ value: String) -> Bool {
        value.utf8.count <= 256 && ArtifactManifest.isSafeRelativePath(value) &&
        value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 47, 95].contains($0) }
    }
    static func healthPath(_ value: String) -> Bool {
        value == "/" || (value.hasPrefix("/") && !value.hasPrefix("//") && executable(String(value.dropFirst())))
    }
    static func environmentName(_ value: String) -> Bool {
        guard value.utf8.count <= 128, let first = value.utf8.first, first == 95 || (65...90).contains(first),
              value.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }) else { return false }
        let reserved = ["PATH", "HOME", "USER", "LOGNAME", "SHELL", "IFS", "ENV", "BASH_ENV", "PYTHONPATH", "PYTHONHOME", "NODE_OPTIONS", "JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "DOTNET_STARTUP_HOOKS", "DOTNET_ADDITIONAL_DEPS"]
        return !reserved.contains(value) && !value.hasPrefix("LD_") && !value.hasPrefix("DYLD_")
    }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func rejectUnknown(_ decoder: any Decoder, allowed: [String]) throws {
        let values = try decoder.container(keyedBy: Key.self)
        guard values.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw invalid("The service definition contains unsupported fields.")
        }
    }
}
