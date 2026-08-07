# CLAUDE.md — funico-server-foundation

The shared foundation for every Funico server, plus the models the Server Manager app and the
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

Build and check them:

```bash
swift package generate-documentation --target ServerFoundationCore
```

**A warning is a failure.** DocC reports dangling ` ``Symbol`` ` links and half-documented parameter
lists as warnings, not errors, so nothing stops you shipping a catalog that no longer resolves. Run
it for every target you touched and expect zero output:

```bash
for t in ServerFoundationCore ServerFoundationLogging ServerFoundationVapor ServerFoundationClient; do
  swift package generate-documentation --target "$t" 2>&1 | grep -E "^warning:|^error:"
done
```

Two things that will bite:

- **DocC cannot link across modules.** ` ``ServerEventEnvelope`` ` from inside `ServerFoundationCore`
  is a dangling link — the type is in `ServerFoundationLogging`. Use a plain code span for anything
  outside the current target.
- **DocC cannot link to extensions on a dependency's type.** `Application.enableAgentControl` is an
  extension on Vapor's `Application`, so it cannot appear in `## Topics` and cannot be referenced
  with double backticks. Document those in prose; `--include-extended-types` does not help.

`swift-docc-plugin` is a real dependency of this package rather than something you install by hand.
It costs every consumer two small extra clones (`swift-docc-plugin`, `swift-docc-symbolkit`), which
is the price of the documentation rule above being checkable in CI instead of aspirational.
Xcode's **Product ▸ Build Documentation** works without it.

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
| `ServerFoundation` | Core + Logging + Vapor | the Vapor servers. Umbrella; `@_exported` re-exports all three |
| `ServerFoundationCore` | *nothing* | app, agent, servers |
| `ServerFoundationLogging` | Core, swift-log | servers, agent, app |
| `ServerFoundationVapor` | Core, Logging, Vapor | Vapor servers only |
| `ServerFoundationClient` | Core, Logging, swift-log | app, agent |

Released: **2.1.0**.

## Rules that are load-bearing

- **`ServerFoundationCore` has zero package dependencies. Keep it that way.** It is what makes this
  importable from an iOS target and from the agent.
- **`ServerFoundationClient` is not in the umbrella.** Servers have no use for a client.
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

Seven repos declare this package. Three can be built locally
(`funico-invoices-service`, `funico-scheduler-api-server`, `funico-authentication-server`); the rest
need credentials for private dependencies. Verify with `swift package edit`, never by editing a
consumer's manifest:

```bash
swift package edit funico-server-foundation --path /path/to/funico-server-foundation
swift build
swift package unedit funico-server-foundation
```

## Versioning and commits

SwiftPM takes versions from git tags — there is no version in `Package.swift`. Tag on `main` after
merge.

Commit messages: imperative subject, then a prose body explaining what changed and why. Match the
existing log.
