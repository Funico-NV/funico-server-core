//
//  ServerFoundationLogging.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

// Deprecated. `ServerFoundationLogging` is the funico-server-foundation 2.x name of `ServerCoreLogging`.
//
// It exists so that moving a consumer from funico-server-foundation to funico-server-core can be
// done as a URL change alone; the imports can follow whenever convenient. Replace
// `import ServerFoundationLogging` with `import ServerCoreLogging` — nothing else changes, because every type kept its name.
//
// Removed in 4.0.0.

@_exported import ServerCoreLogging
