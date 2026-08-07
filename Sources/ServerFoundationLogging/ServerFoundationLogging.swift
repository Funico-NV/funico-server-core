//
//  ServerFoundationLogging.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

// Logging shared by the servers, the agent and the app: ``FNCLog``, ``LogStorage``,
// ``MemoryLogHandler`` and ``ServerEventEnvelope``.
//
// swift-log is not re-exported: Vapor already vends `Logging` into every server's
// namespace, and re-exporting it here would make `Logger` ambiguous at the umbrella.
