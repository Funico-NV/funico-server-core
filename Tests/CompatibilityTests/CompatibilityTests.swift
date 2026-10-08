//
//  CompatibilityTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 08/10/2026.
//

import Testing
import Foundation

#if Vapor
import Vapor
import ServerFoundationVapor
#endif

// Only the 2.x module names are imported here. If a shim stops re-exporting its successor, this
// file stops compiling — which is the failure every unmigrated consumer would otherwise hit first.
import ServerFoundation
import ServerFoundationCore
import ServerFoundationLogging
import ServerFoundationClient

@Test func coreTypesResolveThroughTheOldNames() {
    let state = ServerState.online
    #expect(state.rawValue == "online")

    let query: Query = "SELECT 1"
    #expect(query.sql == "SELECT 1")
}

@Test func loggingTypesResolveThroughTheOldNames() async {
    let storage = LogStorage()
    let envelope = ServerEventEnvelope(sequence: 1, serverID: "invoices", payload: .state(.online))
    #expect(envelope.topic == .state)
    _ = storage
}

@Test func clientExtensionsResolveThroughTheOldNames() throws {
    // `webSocketURL` is an extension on Foundation's `URL`; extension members are only visible
    // when their defining module is imported, so this is the case a typealias shim would miss.
    let url = try #require(URL(string: "https://example.com/v1/events"))
    #expect(url.webSocketURL?.scheme == "wss")
}

#if Vapor
@Test func vaporExtensionResolvesThroughTheOldName() {
    let enableAgentControl = Application.enableAgentControl(version:provider:logs:onShutdownRequest:)
    _ = enableAgentControl
}
#endif
