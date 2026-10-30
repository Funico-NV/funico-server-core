# Remote installation assessments

Review a signed release against host-owned first-installation policy without provisioning anything.

The host's protected `/etc/funico-agent/installations.json` independently authorizes service IDs,
repositories, profiles, signing keys, accounts and roots. This is separate from runtime inventory:
being an installation candidate never grants start, stop, restart, tools or deployment permission.

`listInstallationCandidates` exposes only host-approved identity/profile/platform/quota metadata.
`planInstallation` carries a service, version, repository and three Manager artifact URLs. It never
carries paths, units, account overrides, environment values or signing keys. Older agents decode
new command kinds as unsupported and refuse them. Hosts must be upgraded and bootstrapped explicitly.

The Manager rechecks access through the single configured GitHub App, downloads the three published
assets, checks their checksum and issues a hashed, expiring, per-assessment download token. No GitHub
credential reaches the Agent or browser. The Agent accepts only the configured Manager artifact
host and canonical assessment asset paths, checks fresh local policy before and after inspection,
verifies the pinned signature and samples host facts itself. Policy additions require an Agent
restart; revocations are observed immediately. Configuration values are never read for the report.

The durable Manager job uses a caller-generated UUID bound to actor, host, service and release.
There is one active assessment per host, enforced by a partial unique database index. The browser
must query its saved UUID after uncertain delivery rather than automatically submitting another POST.
A stopped/restarted Manager fails interrupted jobs and revokes their download tokens; assessment
commands are never automatically recovered as installations.

`ServiceInstallationAssessment` is portable review metadata, always `applySupported: false`.
A completed job may contain unmet requirements. `reviewable` means only that this assessment found
no blockers. The fingerprint is not an execution token. Only archive metadata is inspected here:
full extracted-tree verification, fresh policy/facts, protected configuration delivery, explicit
migration authorization and privileged provisioning remain mandatory future work before apply.
