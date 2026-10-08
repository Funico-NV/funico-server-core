//
//  ArtifactManifest.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Foundation

/// `manifest.json` at the root of a release archive: what the build is, what it needs, and the
/// hash of every file in it.
///
/// Written by the release workflow, read by the agent before it installs anything. The agent calls
/// ``validate()`` first, then checks ``service``, ``platform`` and ``minimumAgentVersion`` against
/// itself, then hashes every extracted file against ``files``.
///
/// ```json
/// {
///   "schema": 1,
///   "service": "invoices",
///   "version": "1.6.0",
///   "gitCommit": "4f2a…",
///   "platform": { "os": "linux", "arch": "x86_64" },
///   "entrypoint": "bin/Invoices",
///   "files": { "bin/Invoices": "9c1e…", "lib/libAMSMB2.so": "77ab…" },
///   "requiresMigration": false,
///   "configKeys": ["DATABASE_URL"]
/// }
/// ```
public struct ArtifactManifest: Sendable, Hashable, Codable {

    /// The manifest format this package writes and understands.
    public static let currentSchema = 1

    /// The manifest format. A manifest with a schema newer than ``currentSchema`` is rejected
    /// rather than half-understood.
    public var schema: Int

    /// The service this build is for. Must match the service being deployed — the check that stops
    /// one service's build being installed as another's.
    public var service: ServiceID

    /// The version, without a `v` prefix.
    public var version: String

    /// The commit the build was made from.
    public var gitCommit: String

    /// The platform the build runs on.
    public var platform: ArtifactPlatform

    /// The oldest glibc the binary links against, such as `"2.35"`. `nil` for a static binary.
    public var minimumGlibc: String?

    /// The Swift toolchain the build used. Informational.
    public var swiftVersion: String?

    /// The executable, relative to the release root. systemd starts
    /// `current/<entrypoint>`.
    public var entrypoint: String

    /// Every file in the release, relative to its root, mapped to its hex-encoded SHA-256. A file
    /// present in the archive but absent here fails verification, and so does the reverse.
    public var files: [String: String]

    /// The oldest agent that may install this build.
    public var minimumAgentVersion: String?

    /// Whether this release changes the database schema. The Manager asks for explicit
    /// confirmation before deploying one, and flags a rollback of one: migrations are never
    /// reversed automatically.
    public var requiresMigration: Bool

    /// The HTTP path the agent polls to decide the service is ready, such as `"/health"`.
    public var healthPath: String?

    /// Environment variables the service needs, by name only. The agent checks they are present in
    /// the service's environment file before activating — a missing secret then fails the
    /// deployment while production is still untouched, instead of crashing the new release. Values
    /// never appear in a manifest.
    public var configKeys: [String]

    /// Creates a manifest.
    ///
    /// - Parameters:
    ///   - schema: the manifest format.
    ///   - service: the service this build is for.
    ///   - version: the version, without a `v` prefix.
    ///   - gitCommit: the commit the build was made from.
    ///   - platform: the platform the build runs on.
    ///   - minimumGlibc: the oldest glibc the binary needs.
    ///   - swiftVersion: the toolchain the build used.
    ///   - entrypoint: the executable, relative to the release root.
    ///   - files: every file, relative to the release root, mapped to its SHA-256.
    ///   - minimumAgentVersion: the oldest agent that may install this build.
    ///   - requiresMigration: whether the release changes the database schema.
    ///   - healthPath: the readiness path.
    ///   - configKeys: the environment variables the service needs.
    public init(
        schema: Int = ArtifactManifest.currentSchema,
        service: ServiceID,
        version: String,
        gitCommit: String,
        platform: ArtifactPlatform,
        minimumGlibc: String? = nil,
        swiftVersion: String? = nil,
        entrypoint: String,
        files: [String: String],
        minimumAgentVersion: String? = nil,
        requiresMigration: Bool = false,
        healthPath: String? = nil,
        configKeys: [String] = []
    ) {
        self.schema = schema
        self.service = service
        self.version = version
        self.gitCommit = gitCommit
        self.platform = platform
        self.minimumGlibc = minimumGlibc
        self.swiftVersion = swiftVersion
        self.entrypoint = entrypoint
        self.files = files
        self.minimumAgentVersion = minimumAgentVersion
        self.requiresMigration = requiresMigration
        self.healthPath = healthPath
        self.configKeys = configKeys
    }

    /// Checks the manifest is safe to act on, independent of any particular host.
    ///
    /// The manifest comes out of a downloaded archive, so it is checked *after* the archive's
    /// signature but treated as untrusted input all the same. Rejects:
    ///
    /// - a ``schema`` newer than ``currentSchema``;
    /// - a file path, or the ``entrypoint``, that is empty, absolute, or contains a `..`, `.` or
    ///   empty component — anything that could write or execute outside the release directory;
    /// - an ``entrypoint`` not listed in ``files``;
    /// - a hash that is not 64 hex characters;
    /// - a ``healthPath`` that does not start with `/`, or that names a scheme or host;
    /// - a ``configKeys`` entry that is not a valid environment variable name.
    ///
    /// - Throws: ``ServerCoreError`` with ``ServerCoreError/Code/invalidManifest``, naming the first
    ///   problem found.
    public func validate() throws {
        func invalid(_ message: String) -> ServerCoreError {
            ServerCoreError(.invalidManifest, message)
        }

        guard schema >= 1, schema <= Self.currentSchema else {
            throw invalid("unsupported manifest schema \(schema)")
        }
        guard !files.isEmpty else {
            throw invalid("the manifest lists no files")
        }
        for (path, hash) in files {
            guard Self.isSafeRelativePath(path) else {
                throw invalid("unsafe file path \"\(path)\"")
            }
            guard Self.isSHA256(hash) else {
                throw invalid("\"\(path)\" has a malformed SHA-256")
            }
        }
        guard Self.isSafeRelativePath(entrypoint), files[entrypoint] != nil else {
            throw invalid("entrypoint \"\(entrypoint)\" is not one of the listed files")
        }
        if let healthPath {
            guard healthPath.hasPrefix("/"), !healthPath.hasPrefix("//"), !healthPath.contains("://") else {
                throw invalid("health path \"\(healthPath)\" must be a path starting with /")
            }
        }
        for key in configKeys {
            guard Self.isEnvironmentName(key) else {
                throw invalid("\"\(key)\" is not a valid environment variable name")
            }
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    static func isSHA256(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
        }
    }

    static func isEnvironmentName(_ name: String) -> Bool {
        guard let first = name.utf8.first, !(UInt8(ascii: "0")...UInt8(ascii: "9")).contains(first) else {
            return false
        }
        return name.utf8.allSatisfy { byte in
            byte == UInt8(ascii: "_")
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
        }
    }
}
