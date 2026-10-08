//
//  ServerKit.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

// `ServerKit` is an umbrella that re-exports the split products. Vapor is
// deliberately trait-gated so Core/Logging/Client consumers do not resolve it.
//
// Re-exporting has to be done with `@_exported`. A typealias shim cannot deliver
// `Application.exposeDocumentation`: extension members are only visible when the
// module that defines them is imported, so aliasing the types is not enough.
//
// `@_exported` is an underscored attribute and formally unsupported. It is used by
// Vapor itself and is stable on Swift 6.x, but it is not a language guarantee. If a
// future toolchain drops it, the fallback is explicit per-product imports in the
// consuming repos.

@_exported import ServerCore
@_exported import ServerCoreLogging

#if Vapor
@_exported import ServerCoreVapor
#endif
