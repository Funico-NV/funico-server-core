import Foundation

/// A portable, review-only host report. Decoding never enables application or accepts configuration values.
public struct ServiceInstallationAssessment: Sendable, Hashable, Codable {
    /// Fingerprint of policy, inspected archive/definition, service and local facts; not an execution token.
    public let reviewBinding: String
    /// First-install identity selected from host policy.
    public let service: ServiceID
    /// Repository fixed in the host permission, not asserted by the archive.
    public let repository: String
    /// Version of the signed archive whose metadata was inspected.
    public let version: String
    /// The exact archive the assessment refers to.
    public let archiveSHA256: String
    /// Exact definition bytes used for metadata and setting validation.
    public let definitionSHA256: String
    /// Host-approved key that accepted the signature.
    public let signingKeySHA256: String
    /// Requested and host-matched profile name.
    public let profile: String
    /// Host-selected supervisor intent.
    public let backend: String
    /// Host-selected non-root account.
    public let serviceUser: String
    /// Host-selected systemd unit, absent for supervised processes.
    public let unit: String?
    /// Fixed per-service root derived from host policy.
    public let installRoot: String
    /// Fixed environment file derived from host policy, never chosen by a repository.
    public let environmentFile: String
    /// Executable relative to the verified release; this command does not start it.
    public let executable: String
    /// Literal argv from signed metadata; no substitutions or shell interpretation are performed.
    public let arguments: [String]
    /// Fixed loopback readiness target when declared and permitted.
    public let readinessURL: String?
    /// Separate migration authorization will be needed before application.
    public let requiresMigration: Bool
    /// Declared setting classifications and where a value would come from; values are omitted.
    public let settings: [Setting]
    /// Fixed diagnostics for unmet requirements, without configuration values or raw artifact errors.
    public let issues: [String]
    /// True only means this assessment has no currently known unmet requirements.
    /// It never grants execution permission; full-tree verification and provisioning remain unimplemented.
    public let reviewable: Bool
    /// Always false in this planning-only implementation, even if every assessment check passes.
    public let applySupported: Bool
    /// Mandatory work for a future apply path; this assessment cannot stand in for those checks.
    public let requiredBeforeApply: [String]

    /// Display metadata for one setting; there is deliberately no value/defaultValue property.
    public struct Setting: Sendable, Hashable, Codable {
        /// Key from the signed definition.
        public let name: String
        /// Validation type from the shared definition.
        public let type: ServiceEnvironmentDefinition.ValueType
        /// Whether activation requires a value.
        public let required: Bool
        /// Whether future configuration delivery/storage must keep it write-only.
        public let secret: Bool
        /// accepted, repositoryDefault, missing or omitted. This names a source without returning a value.
        public let source: String
    }

    private enum CodingKeys: String, CodingKey { case reviewBinding, service, repository, version, archiveSHA256, definitionSHA256, signingKeySHA256, profile, backend, serviceUser, unit, installRoot, environmentFile, executable, arguments, readinessURL, requiresMigration, settings, issues, reviewable, applySupported, requiredBeforeApply }
    /// Decodes only a bounded, coherent review report; an apply-capable report is unsupported.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewBinding = try c.decode(String.self, forKey: .reviewBinding)
        service = try c.decode(ServiceID.self, forKey: .service)
        repository = try c.decode(String.self, forKey: .repository)
        version = try c.decode(String.self, forKey: .version)
        archiveSHA256 = try c.decode(String.self, forKey: .archiveSHA256)
        definitionSHA256 = try c.decode(String.self, forKey: .definitionSHA256)
        signingKeySHA256 = try c.decode(String.self, forKey: .signingKeySHA256)
        profile = try c.decode(String.self, forKey: .profile)
        backend = try c.decode(String.self, forKey: .backend)
        serviceUser = try c.decode(String.self, forKey: .serviceUser)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        installRoot = try c.decode(String.self, forKey: .installRoot)
        environmentFile = try c.decode(String.self, forKey: .environmentFile)
        executable = try c.decode(String.self, forKey: .executable)
        arguments = try c.decode([String].self, forKey: .arguments)
        readinessURL = try c.decodeIfPresent(String.self, forKey: .readinessURL)
        requiresMigration = try c.decode(Bool.self, forKey: .requiresMigration)
        settings = try c.decode([Setting].self, forKey: .settings)
        issues = try c.decode([String].self, forKey: .issues)
        reviewable = try c.decode(Bool.self, forKey: .reviewable)
        applySupported = try c.decode(Bool.self, forKey: .applySupported)
        requiredBeforeApply = try c.decode([String].self, forKey: .requiredBeforeApply)
        try validate()
    }

    /// Checks wire bounds and review-only semantics before a Manager publishes this report.
    public func validate() throws {
        guard !applySupported, reviewable == issues.isEmpty, ["systemd", "supervised"].contains(backend),
              InstallationWire.slug(service.rawValue), InstallationWire.slug(profile), InstallationWire.repository(repository),
              [reviewBinding, archiveSHA256, definitionSHA256, signingKeySHA256].allSatisfy(InstallationWire.digest),
              InstallationWire.text(version, maximum: 64), InstallationWire.text(serviceUser, maximum: 32),
              unit.map({ InstallationWire.text($0, maximum: 128) }) ?? true,
              InstallationWire.path(installRoot), InstallationWire.path(environmentFile),
              InstallationWire.text(executable, maximum: 256), arguments.count <= 32,
              arguments.allSatisfy({ InstallationWire.text($0, maximum: 2048, empty: true) }),
              arguments.reduce(0, { $0 + $1.utf8.count }) <= 8192,
              readinessURL.map({ InstallationWire.text($0, maximum: 512) }) ?? true,
              settings.count <= 64, Set(settings.map(\.name)).count == settings.count,
              settings.allSatisfy({ InstallationWire.environment($0.name) && ["accepted", "repositoryDefault", "missing", "omitted"].contains($0.source) }),
              issues.count <= 32, issues.allSatisfy({ InstallationWire.text($0, maximum: 64) }),
              !requiredBeforeApply.isEmpty, requiredBeforeApply.count <= 16,
              requiredBeforeApply.allSatisfy({ InstallationWire.text($0, maximum: 64) }),
              try JSONEncoder().encode(self).count <= 65_536 else { throw InstallationWire.invalid() }
    }
}

/// A service the host explicitly permits considering for first installation. It is not runtime inventory.
public struct ServiceInstallationCandidate: Sendable, Hashable, Codable {
    /// Host-approved service identifier.
    public var service: ServiceID
    /// Host-approved owner/name; never a user-supplied repository override.
    public var repository: String
    /// Host-approved profile name.
    public var profile: String
    /// Profile platform, chosen by the host rather than a browser.
    public var platform: ArtifactPlatform
    /// False when profile/platform intent does not match this host.
    public var platformCompatible: Bool
    /// Existing services must use deployment/adoption, not first-install overwrite.
    public var alreadyManaged: Bool
    /// Host quota, also enforced again by the Agent before download/inspection.
    public var maximumArchiveBytes: Int64

    /// Creates public planning metadata without exposing keys, paths or configuration values.
    public init(service: ServiceID, repository: String, profile: String, platform: ArtifactPlatform,
                platformCompatible: Bool, alreadyManaged: Bool, maximumArchiveBytes: Int64) {
        self.service = service; self.repository = repository; self.profile = profile; self.platform = platform
        self.platformCompatible = platformCompatible; self.alreadyManaged = alreadyManaged; self.maximumArchiveBytes = maximumArchiveBytes
    }
    /// Rejects malformed metadata before it becomes Manager release-selection input.
    public func validate() throws {
        guard InstallationWire.slug(service.rawValue), InstallationWire.slug(profile), InstallationWire.repository(repository),
              ["linux", "macos"].contains(platform.os), ["x86_64", "aarch64"].contains(platform.arch),
              (1...536_870_912).contains(maximumArchiveBytes) else { throw InstallationWire.invalid() }
    }
}

/// A read-only assessment request. Paths, accounts, units, environment values and trust anchors are absent.
public struct InstallationPlanRequest: Sendable, Hashable, Codable {
    /// An ID approved by the separate host installation policy.
    public var service: ServiceID
    /// Exact release version, checked against signed metadata.
    public var version: String
    /// Repository fixed by the host, rechecked by the Agent; it is not a download URL.
    public var repository: String
    /// Three Manager-hosted assets. GitHub credentials never reach the Agent.
    public var artifact: ReleaseArtifact
    /// Creates a request for assessment only; it cannot activate or migrate a service.
    public init(service: ServiceID, version: String, repository: String, artifact: ReleaseArtifact) {
        self.service = service; self.version = version; self.repository = repository; self.artifact = artifact
    }
    /// Checks bounded identity/version metadata. Network source restrictions remain host policy.
    public func validate() throws {
        guard InstallationWire.slug(service.rawValue), InstallationWire.repository(repository),
              InstallationWire.text(version, maximum: 64), !version.contains(".."),
              version.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95,43].contains($0) }),
              artifact.size.map({ (1...536_870_912).contains($0) }) ?? true else { throw InstallationWire.invalid() }
    }
}

private enum InstallationWire {
    static func invalid() -> ServerCoreError { .init(.invalidRequest, "Unsupported or invalid installation assessment metadata.") }
    static func text(_ s: String, maximum: Int, empty: Bool = false) -> Bool {
        (empty || !s.isEmpty) && s.utf8.count <= maximum && s.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    static func slug(_ s: String) -> Bool {
        text(s, maximum: 64) && !s.contains("..") && s.utf8.first.map({ (97...122).contains($0) || (48...57).contains($0) }) == true &&
        s.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || [45,46,95].contains($0) }
    }
    static func repository(_ s: String) -> Bool {
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 100 && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) } }
    }
    static func digest(_ s: String) -> Bool { s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func environment(_ s: String) -> Bool {
        (try? ServiceEnvironmentDefinition(name: s, title: s, type: .string, required: false, secret: false)) != nil
    }
    static func path(_ s: String) -> Bool { text(s, maximum: 1024) && s.hasPrefix("/") }
}
