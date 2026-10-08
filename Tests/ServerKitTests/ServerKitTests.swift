//
//  ServerKitTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 26/12/2025.
//

import Testing
import Foundation

#if Vapor
import Vapor
#endif

import ServerKit

// These tests guard the umbrella, not the logic — the logic is covered in
// ServerCoreTests. What can regress here is the `@_exported` re-export:
// if it stops working, every consumer breaks at once with "cannot find X in scope".

@Test func umbrellaReExportsCoreTypes() {
    let query: Query = "SELECT 1"
    #expect(query.sql == "SELECT 1")

    guard case .missingField(let field) = APIModelError.missingField("id") else {
        Issue.record("APIModelError did not re-export with its cases intact")
        return
    }
    #expect(field == "id")
}

#if Vapor
@Test func umbrellaReExportsVaporExtension() {
    // Referencing the unapplied method is the whole assertion, and it is checked at
    // compile time. Extension members are only visible when their defining module is
    // imported, so this line stops compiling the moment the umbrella drops
    // `@_exported import ServerCoreVapor` — which is exactly the failure a
    // typealias-based shim would have shipped silently.
    let exposeDocumentation = Application.exposeDocumentation(file:extension:in:)
    _ = exposeDocumentation
}
#endif
