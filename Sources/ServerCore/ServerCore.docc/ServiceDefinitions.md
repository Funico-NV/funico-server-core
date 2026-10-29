# Service definitions

Describe installation intent without granting a repository authority over the host.

## A file beside the service source

A service repository can carry `funico-service.json`, represented by ``ServiceDefinition``.
The build also includes that exact file in the release archive and hashes it in
``ArtifactManifest/files``. A mutable branch copy is discovery metadata only: installation
must use the definition from the verified signed release that the operator reviewed.

The format is schema 1, at most 64 KiB. Unknown fields, unsupported versions/platforms,
explicit nulls in optional fields, duplicate environment names and duplicate platforms
are refused. The four objects are strictly decoded, including nested declarations.
`Packaging/service-definition.schema.json` supplies editor assistance; the Swift validator
is authoritative and applies byte limits and semantic checks beyond JSON Schema.

```swift
import Foundation
import ServerCore

let bytes = Data(#"{"schema":1,"service":"example","displayName":"Example","profile":"application","platforms":[{"os":"linux","arch":"x86_64","executable":"bin/Example"}]}"#.utf8)
let definition = try ServiceDefinition.decode(bytes)
let runtime = definition.runtime(for: .linuxX86_64)
print(runtime?.executable ?? "Unsupported platform")
```

## Host authority stays on the host

``ServiceDefinition/profile`` is a request for an already approved policy profile.
It cannot create a root user, change signing trust, nominate an arbitrary installation
root or run an installation script. The Agent must validate host policy independently.
Neither decoding this file nor running the validator installs a service. Provisioning
commands and configuration delivery are a separate integration stage.

``ServiceRuntimeDefinition`` names an executable relative to the verified release tree.
Arguments are an array of literal strings, passed without a shell. `$VALUE`, spaces,
quotes and shell-looking text remain literal; they are never environment substitution.
A backend must preserve argv boundaries rather than concatenate a command string.
Linux and macOS metadata can be expressed, but a platform is installable only when an
actual Agent backend advertises the required capability and policy profile.

``ServiceReadinessDefinition`` describes a GET on loopback, with an unprivileged port,
bounded timing and a simple absolute path. No URL, remote host, query, fragment, encoded
characters or traversal segments are accepted. The Agent chooses loopback itself;
repository metadata must never be resolved as a relative URL against a remote host.

## Configuration schema and secret classification

``ServiceEnvironmentDefinition`` describes a setting by name/title, type, requiredness
and secret classification. Requiredness and secrecy are explicit in JSON. Secret
values cannot be defaulted or embedded in the definition. An unknown `value` field is
rejected. An optional value is omitted; null is not a keep/delete operation.

Defaults and runtime values are strings, including integers and booleans. Integer
values are canonical signed 64-bit strings; numeric bounds use JSON-safe integers.
Boolean values are exactly `true` or `false`. URL settings are HTTP(S) endpoints
without user-info or fragments; a PostgreSQL connection string belongs in a secret
string setting. String choices are optional finite vocabularies. Unicode control
characters, NUL/newlines and known runtime-injection/environment-control names are
refused. The list is a conservative baseline, not a substitute for host policy.

Values supplied later through configuration APIs must be checked with
``ServiceEnvironmentDefinition/validateValue(_:)`` before delivery. Its errors do not
include the supplied value. Secret storage, write-only API behavior, audit redaction
and restart/apply policy still need to be implemented by those APIs and the Agent.

## Bind intent to the release

After verifying archive signature and all extracted file hashes, the Agent can call
``ServiceDefinition/validate(for:)``. This checks service, file inclusion, platform,
entrypoint, migration flag, readiness path and required configuration names against
``ArtifactManifest``. It is not itself a cryptographic verification. Merely having a
file named `funico-service.json` on a branch or in an archive is insufficient.

The build-side `funico-service-validate` executable checks bounded input and optional
manifest agreement. It does not possess signing keys or change running services:

```sh
swift run funico-service-validate Packaging/Examples/funico-service.json
swift run funico-service-validate path/to/funico-service.json --manifest path/to/manifest.json
```

Legacy releases without a service definition continue to use their existing deployment
contract. New-service installation must require a definition and host provisioning
support; it must not infer an installation recipe from the legacy entrypoint alone.
