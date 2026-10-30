# Protected service configuration

Save host-approved environment changes without disclosing current values or implicitly restarting a service.

## Authority and storage

The separate root-owned `/etc/funico-agent/configuration.json` policy fixes each service's exact
file and typed schema. It has no values/defaults and is bounded to 64 KiB. Unknown fields, duplicate
files/names, reserved process variables and unsupported versions are rejected. New IDs require an
Agent restart; policy changes and revocations are reloaded on every read/save.

For this milestone, only prepared Linux systemd environments can be saved. macOS reports read-only
metadata; persistent integration with its supervised process environment remains future work.
Configuration permission does not grant service operations, deployment, enrollment or installation.

Prepare a dedicated Agent-owned `0700` directory and `0600` environment file, preferably under its
existing StateDirectory. Ancestors must be protected; original system symlinks are checked and POSIX
realpath/openat pins the physical directory. Final symlinks, non-regular files, hard links, writable
parents and unmanaged legacy files are refused. All readers/writers take a nonblocking file lock.
A canonical quoted UTF-8 format passes values literally, with no shell/variable expansion.
The temporary file is flushed, compared against the reviewed version, atomically renamed and the
directory flushed. No general `/etc` write permission or root Agent is introduced.

Existing root-owned legacy files require a separate administrative migration and matching systemd
EnvironmentFile configuration. Do not chown them broadly or expose a remote path/command override.
Values necessarily enter the service's process environment after restart: this is not a secret vault
or a replacement for systemd credentials/secret files. Protect host access and encrypted backups.

## Delivery and optimistic concurrency

Read returns only approved field names, types, requiredness, secrecy and presence. Every value is
write-only, including non-secret values. Missing keys in a patch are kept; set/replace and remove
are explicit. Removing required keys, missing required values, unknown names, invalid types/bounds,
control characters and oversized patches are refused without echoing input.

A snapshot includes an opaque HMAC revision over policy, service and current file, with a random
process-local key; it is not a public hash enabling guesses of low-entropy secrets. Manager obtains
an ephemeral public recipient key over the enrolled Agent channel and uses Swift Crypto's standard
RFC 9180 HPKE implementation (X25519, HKDF-SHA256, AES-256-GCM). Operation UUID, enrolled host, service,
revision, key identity and expiry are authenticated. The private key is never serialized. Restarting
the Agent invalidates old encrypted requests. HPKE base mode does not authenticate its sender:
Manager token/role checks and the enrolled authenticated channel remain mandatory.

HTTP inputs exist transiently in Manager memory. They are encrypted before Agent dispatch; only
ciphertext can enter Agent command journals. Manager records contain identity/state/receipt metadata,
never plaintext changes. Ordinary descriptions and diagnostics redact values. This does not protect
against a compromised Manager process or a compromised host, which can access their live memory.

## Operation and recovery semantics

Read sees metadata/status; Operate can create a save. Every mutation is audited without values.
The caller chooses a canonical UUID before submission. A previously claimed UUID is refused; query
its original host/service operation with GET. A partial unique SQL index limits active saves per
service. Agent commands share the normal per-service queue with deployments and lifecycle actions.
Known command UUIDs are answered from the journal rather than executed again.

Interrupted/expired Manager jobs are failed without redispatch. A failure can mean an uncertain
outcome after atomic replacement; it is never presented as proof that nothing changed. The file
stamps the operation UUID atomically with its values. A fresh metadata read exposes `lastOperationID`
without values, allowing confirmation after a lost response or Agent restart. Subsequent writes can
supersede that marker. Always refresh/review before a new submission; never retry writes automatically.

Saving returns `restartRequired: true` and never calls a backend, reloads a unit, or restarts a service.
Activation remains a separate confirmed action. Automatic configuration rollback/history is not
implemented; a binary rollback is not a configuration or database rollback.

## First installations

Configuration may be prepared for a separately host-approved candidate without making it runtime
inventory. Installation assessment recognizes the exact managed environment path only when protected
configuration policy and the signed release agree and stored values satisfy both schemas. It reports
accepted names, not values. Plans remain `applySupported: false`: full extracted-tree verification,
fresh configuration binding, privileged resource provisioning and installation recovery are still
required before first-install application. Existing Authentication configuration is not modified.
