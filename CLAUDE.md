# CLAUDE.md — funico-server-core

Formerly funico-server-foundation (renamed in 3.0.0). The shared foundation for every Funico server, plus the models the Server Manager app and the
deploy agent need. Cross-repo architecture lives in
[`../../Funico Server Manager/server-manager-plan.md`](../../Funico%20Server%20Manager/server-manager-plan.md).

---

## Documentation is part of the change, not a follow-up

**A change is not done when it compiles and the tests pass. It is done when the documentation says
what it now does.** Both of the following ship in the same commit as the code.

### 1. Swift DocC

Every target has a catalog at `Sources/<Target>/<Target>.docc/`. Keep it current:

| You did this | Then do this |
|---|---|
| Added a public type or method | Doc comment on the symbol, and add it to the catalog's `## Topics` if a caller reaches for it directly |
| Changed behaviour | Fix the prose describing the old behaviour **first** — a stale doc comment is worse than none, because it gets believed |
| Renamed or removed a symbol | Update every reference; a dangling ` ``Symbol`` ` link breaks the catalog build |
| Added a whole area of functionality | A new article in the catalog, linked from the landing page |

Write doc comments for the caller, not the compiler. `/// The port.` on a property called `port`
is noise. Say what it is *for*, what happens at the boundaries, and what will bite — the reason a
value is what it is belongs in the docs, not only in a commit message.

Check them before you commit:

```bash
Scripts/check-documentation.sh
```

Add `--clean` after removing a public symbol — an incremental build recompiles nothing and so emits
no fresh symbol graphs.

**A warning is a failure, and the tool will not tell you so.** DocC reports dangling ` ``Symbol`` `
links and half-documented parameter lists as *warnings* and still exits 0. The script exists to turn
those into a non-zero exit; that is its whole job.

There is deliberately **no `swift-docc-plugin` dependency**. SwiftPM resolves manifest-level
dependencies for every consumer whether they use them or not, and this package has seven of them.
The script drives `docc` directly and needs nothing beyond the toolchain. Xcode's
**Product ▸ Build Documentation** also works.

Three things that will bite:

- **DocC cannot link across modules.** ` ``ServerEventEnvelope`` ` from inside
  `ServerCore` is a dangling link — the type is in `ServerCoreLogging`. Use a plain
  code span for anything outside the current target.
- **DocC cannot link to extensions on a dependency's type.** `Application.enableAgentControl` and
  `URL.webSocketURL` are extensions on Vapor's and Foundation's types, so they cannot appear in
  `## Topics` and cannot be referenced with double backticks. Document them in prose;
  `--include-extended-types` does not help.
- **Parameter lists are all-or-nothing.** Document one parameter and DocC demands the rest.

### 3. Examples must actually compile

Every Swift block in the README and in a DocC catalog is code someone will paste. Extract them into
a scratch package and build it — this has already caught a `@Sendable` closure capturing a mutable
`var`, which would not have compiled for anyone who copied it. Blocks in one document may build on
each other; concatenate per document rather than compiling each in isolation.

### 2. README.md, with at least one example

The README always carries **at least one Swift example per product**, showing the basic use — the
thing a newcomer needs to type to get going. Requirements:

- It must compile against the current API. An example that no longer builds is a bug report from
  the future.
- It shows the *ordinary* path, not an exhaustive tour. Enough to be obviously usable, short
  enough to be read at a glance.
- If a change breaks an example, fix the example in the same commit.

If a product has no example, it is not finished.

### Definition of done

- [ ] Code compiles, `swift test` passes
- [ ] Doc comments on every new or changed public symbol
- [ ] DocC catalog updated (Topics, articles, no dangling links)
- [ ] README example added or updated, and it still compiles
- [ ] Consumers still build — see below

---

## What this package is

| Product | Depends on | Consumers |
|---|---|---|
| `ServerKit` | Core + Logging + Vapor | the Vapor servers. Umbrella; `@_exported` re-exports all three |
| `ServerCore` | *nothing* | app, agent, servers |
| `ServerCoreLogging` | Core, swift-log | servers, agent, app |
| `ServerCoreVapor` | Core, Logging, Vapor | Vapor servers only |
| `ServerCoreClient` | Core, Logging, swift-log | app, agent |
| `ServerFoundation`, `ServerFoundationCore`, … | the 3.x product of the same role | **deprecated** 2.x names, one `@_exported import` each, under `Sources/Compatibility/`. No catalogs. Removed in 4.0.0 |

Released: **2.1.1** as funico-server-foundation; **3.0.0** is the first release as funico-server-core.

## Rules that are load-bearing

- **`ServerCore` has zero package dependencies. Keep it that way.** It is what makes this
  importable from an iOS target and from the agent.
- **`ServerCoreClient` is not in the umbrella.** Servers have no use for a client.
- **The compatibility shims re-export and nothing else.** No code, no new symbols, no catalogs: they
  exist so a consumer can change the package URL before it changes its imports.
- **Never create a repository called `funico-server-foundation` again.** GitHub's redirect from the
  old name to this repository is what keeps unmigrated consumers building; a new repository with the
  old name breaks that redirect.
- **`ServerJobState` implements `Codable` by hand and must keep doing so.** It conforms to both
  `RawRepresentable` and `Codable`, and the stdlib's
  `extension RawRepresentable where RawValue: Codable, Self: Codable` defaults take precedence over
  synthesis. Delete the explicit implementation and JSON silently routes through the lossy legacy
  string, losing a job's failure reason on the exact path built to carry it.
- **The legacy `"id;iso8601"` codec is frozen.** It is `@AppStorage`'s *persistence* codec on real
  devices, and the service cannot be upgraded atomically with an App Store build. New traffic uses
  `ServerEventEnvelope`.
- **Control-channel responses encode through `AgentControlCoding`, not Vapor's global encoder.**
  `ContentConfiguration.global` is process-wide and writable; a managed server installing its own
  encoder would otherwise silently change what the agent receives.

## Before you call a change done

Eight repos declare this package: `funico-server-agent`, `funico-invoices-service`,
`funico-authentication-api-server`, `funico-scheduler-api-server`, `funico-dashboard-api-server`,
`funico-kpi-api-server`, `funico-dashboard-web` and `funico-dashboard-manager-web`. Three can be built
locally (`funico-invoices-service`, `funico-scheduler-api-server`, `funico-authentication-api-server`);
the rest need credentials for private dependencies. Verify with `swift package edit`, never by
editing a consumer's manifest. A consumer that still declares the old URL knows this package as
`funico-server-foundation`, so use that identity in the commands below until it has migrated:

```bash
swift package edit funico-server-core --path /path/to/funico-server-core
swift build
swift package unedit funico-server-core
```

## Versioning and commits

SwiftPM takes versions from git tags — there is no version in `Package.swift`. Tag on `main` after
merge.

Commit messages: imperative subject, then a prose body explaining what changed and why. Match the
existing log.
