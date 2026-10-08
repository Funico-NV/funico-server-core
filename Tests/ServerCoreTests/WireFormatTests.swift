//
//  WireFormatTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Testing
import Foundation
import ServerCore

// The legacy `"id;iso8601"` codec is not merely a wire format — it is `@AppStorage`'s
// *persistence* codec on real devices. If it drifts, a user's saved job selection silently
// disappears on upgrade, and the service cannot be shipped atomically with an App Store
// build. So these tests assert exact bytes, against an oracle built independently of the
// implementation rather than by calling back into it.

/// Configured exactly as `funico-invoices-api`'s `Date.iso8601String` is today.
private func expectedISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private let fixedDate = Date(timeIntervalSince1970: 1_770_000_000.25)

// MARK: - ServerState

@Test func serverStateRendersTheDatelessCasesAsBareIdentifiers() {
    #expect(ServerState.online.rawValue == "online")
    #expect(ServerState.offline.rawValue == "offline")
    #expect(ServerState.inactive.rawValue == "inactive")
    #expect(ServerState.unknown.rawValue == "unknown")
}

@Test func serverStateRendersMaintenanceWithASemicolonAndISO8601() {
    let state = ServerState.maintenance(since: fixedDate)

    #expect(state.rawValue == "maintenance;\(expectedISO8601(fixedDate))")
}

@Test func serverStateDateFormatKeepsFractionalSecondsAndTheZulUSuffix() {
    // Pinned shape, so that dropping `.withFractionalSeconds` — which still round-trips
    // through our own parser and would pass a naive test — fails here instead.
    let rawValue = ServerState.maintenance(since: fixedDate).rawValue

    #expect(rawValue.wholeMatch(of: /maintenance;\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil)
}

@Test func serverStateRoundTripsEveryCase() throws {
    let cases: [ServerState] = [.online, .offline, .inactive, .unknown, .maintenance(since: fixedDate)]

    for state in cases {
        let decoded = try #require(ServerState(rawValue: state.rawValue))
        #expect(decoded == state)
    }
}

@Test func serverStateRejectsUnparseableInput() {
    #expect(ServerState(rawValue: "definitely-not-a-state") == nil)
    #expect(ServerState(rawValue: "maintenance") == nil)          // needs a date
    #expect(ServerState(rawValue: "a;b;c") == nil)                // over-segmented
}

// MARK: - ServerJobState

@Test func serverJobStateRendersTheLegacyIdentifiers() {
    let iso = expectedISO8601(fixedDate)

    #expect(ServerJobState.executing(since: fixedDate).rawValue == "executing;\(iso)")
    #expect(ServerJobState.running(since: fixedDate).rawValue == "running;\(iso)")
    #expect(ServerJobState.paused(on: fixedDate).rawValue == "paused;\(iso)")
    #expect(ServerJobState.idle(since: fixedDate).rawValue == "idle;\(iso)")
}

@Test func everyFinishedResultStillRendersAsCanceledOnTheLegacyWire() {
    let iso = expectedISO8601(fixedDate)

    // Not a bug being preserved by accident — the legacy vocabulary has exactly one
    // terminal state, and widening it is what breaks a shipped build's persisted value.
    #expect(ServerJobState.finished(.completed, on: fixedDate).rawValue == "canceled;\(iso)")
    #expect(ServerJobState.finished(.cancelled, on: fixedDate).rawValue == "canceled;\(iso)")
    #expect(ServerJobState.finished(.failed("boom"), on: fixedDate).rawValue == "canceled;\(iso)")
}

@Test func theLegacyCanceledIdentifierDecodesToAFinishedState() throws {
    let decoded = try #require(ServerJobState(rawValue: "canceled;\(expectedISO8601(fixedDate))"))

    #expect(decoded == .finished(.cancelled, on: fixedDate))
}

@Test func serverJobStateRoundTripsTheNonTerminalCases() throws {
    let cases: [ServerJobState] = [
        .executing(since: fixedDate),
        .running(since: fixedDate),
        .paused(on: fixedDate),
        .idle(since: fixedDate)
    ]

    for state in cases {
        let decoded = try #require(ServerJobState(rawValue: state.rawValue))
        #expect(decoded == state)
    }
}

@Test func serverJobStateRequiresBothSegments() {
    #expect(ServerJobState(rawValue: "idle") == nil)
    #expect(ServerJobState(rawValue: "idle;not-a-date") == nil)
    #expect(ServerJobState(rawValue: "nonsense;\(expectedISO8601(fixedDate))") == nil)
}

@Test func serverJobStateAcceptsDatesWithoutFractionalSeconds() throws {
    // The original parser falls back to whole seconds. A server on an older build still
    // emits those, so dropping the fallback would break live traffic.
    let decoded = try #require(ServerJobState(rawValue: "idle;2026-08-07T09:15:30Z"))

    #expect(decoded.id == "idle")
}

// MARK: - The lossless path

@Test func jsonEncodingKeepsTheJobResultThatTheLegacyStringLoses() throws {
    let state = ServerJobState.finished(.failed("database unreachable"), on: fixedDate)

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(ServerJobState.self, from: data)

    #expect(decoded == state)
    #expect(decoded.title == "Failed")
    #expect(decoded.failureReason == "database unreachable")

    // The same value through the legacy codec collapses — which is the whole reason the
    // envelope exists.
    let viaLegacy = ServerJobState(rawValue: state.rawValue)
    #expect(viaLegacy == .finished(.cancelled, on: fixedDate))
}

@Test func aSuccessfulAndAFailedRunAreDistinguishableInJSON() throws {
    let completed = ServerJobState.finished(.completed, on: fixedDate)
    let failed = ServerJobState.finished(.failed("nope"), on: fixedDate)

    let encoder = JSONEncoder()
    #expect(try encoder.encode(completed) != encoder.encode(failed))
    #expect(completed.title != failed.title)
}

// MARK: - ServerJob

@Test func serverJobEncodesAsABareString() throws {
    let data = try JSONEncoder().encode(ServerJob("Process"))

    #expect(String(decoding: data, as: UTF8.self) == "\"Process\"")
    #expect(try JSONDecoder().decode(ServerJob.self, from: data) == ServerJob("Process"))
}

@Test func serverJobIsExtensibleWithoutTouchingFoundation() {
    // The Notification.Name pattern: a downstream package adds its own vocabulary.
    #expect(ServerJob("Process") == "Process")
    #expect(ServerJob("Process") != ServerJob("Lookup"))
}

@Test func serverJobDescriptorReportsCapabilities() {
    let descriptor = ServerJobDescriptor(
        job: "Process",
        title: "Process",
        autoStart: true,
        capabilities: [.start, .stop, .execute]
    )

    #expect(descriptor.id == "Process")
    #expect(descriptor.supports(.execute))
    #expect(descriptor.supports(.pause) == false)
}

@Test func serverJobDescriptorRoundTripsThroughJSON() throws {
    let descriptor = ServerJobDescriptor(
        job: "Lookup", title: "Lookup", autoStart: false, capabilities: [.start, .stop]
    )

    let data = try JSONEncoder().encode(descriptor)
    #expect(try JSONDecoder().decode(ServerJobDescriptor.self, from: data) == descriptor)
}
