import Foundation
import ServerCore

/// Builder-side validation only. No installation, credentials or signature assertions.
func readBounded(_ path: String, maximum: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximum + 1) ?? Data()
    guard !data.isEmpty, data.count <= maximum else { throw ValidationFailure() }
    return data
}
struct ValidationFailure: Error {}
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] {
    print("Usage: funico-service-validate DEFINITION.json [--manifest manifest.json]")
    print("Checks syntax, policy constraints and optional manifest agreement. It does not verify signatures or install a service.")
} else if arguments.count == 1 || (arguments.count == 3 && arguments[1] == "--manifest") {
    do {
        let definition = try ServiceDefinition.decode(readBounded(arguments[0], maximum: ServiceDefinition.maximumBytes))
        if arguments.count == 3 {
            let artifact = try JSONDecoder().decode(ArtifactManifest.self, from: readBounded(arguments[2], maximum: 1_048_576))
            try definition.validate(for: artifact)
        }
        print("Valid service definition: \(definition.service.rawValue), \(definition.platforms.count) platform(s), \(definition.environment.count) setting(s).")
        if arguments.count == 3 { print("Manifest agreement checked. Signature and file hashes must still be verified by the Agent.") }
    } catch let error as ServerCoreError {
        FileHandle.standardError.write(Data(("Invalid definition: " + error.message + "\n").utf8))
        exit(1)
    } catch {
        FileHandle.standardError.write(Data("Could not read a bounded, valid definition or artifact manifest.\n".utf8))
        exit(1)
    }
} else {
    FileHandle.standardError.write(Data("Usage: funico-service-validate DEFINITION.json [--manifest manifest.json]\n".utf8))
    exit(2)
}
