//
//  ServerFoundation.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

// `ServerFoundation` is an umbrella that re-exports the split products, so every
// existing consumer keeps working with a single `import ServerFoundation` and a
// one-line bump to `from: Version(2,0,0)` — no source changes.
//
// Re-exporting has to be done with `@_exported`. A typealias shim cannot deliver
// `Application.exposeDocumentation`: extension members are only visible when the
// module that defines them is imported, so aliasing the types is not enough.
//
// `@_exported` is an underscored attribute and formally unsupported. It is used by
// Vapor itself and is stable on Swift 6.x, but it is not a language guarantee. If a
// future toolchain drops it, the fallback is explicit per-product imports in the
// consuming repos — the blast radius is this file.

@_exported import ServerFoundationCore
@_exported import ServerFoundationLogging
@_exported import ServerFoundationVapor
