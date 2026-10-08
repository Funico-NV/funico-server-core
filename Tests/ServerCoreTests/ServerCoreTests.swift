//
//  ServerCoreTests.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Testing
import ServerCore

@Test func queryFromStringLiteral() {
    let query: Query = "SELECT TOP 1 * FROM dbo.Item"
    #expect(query.sql == "SELECT TOP 1 * FROM dbo.Item")
}

@Test func queryInterpolatesStrings() {
    let table = "dbo.Item"
    let query: Query = "SELECT * FROM \(table)"
    #expect(query.sql == "SELECT * FROM dbo.Item")
}

@Test func queryInterpolatesNestedQueries() {
    let columns: Query = "id, name"
    let query: Query = "SELECT \(columns) FROM dbo.Item"
    #expect(query.sql == "SELECT id, name FROM dbo.Item")
}

@Test func sqlQueryConformanceResolvesStaticQuery() {
    struct Item: SQLQuery {
        static var query: Query { "SELECT * FROM dbo.Item" }
    }
    #expect(Item.query.sql == "SELECT * FROM dbo.Item")
}

@Test func apiModelErrorCarriesFieldContext() {
    guard case .invalidFieldType(let field, let expected) =
            APIModelError.invalidFieldType("qty", expectedType: "Int") else {
        Issue.record("unexpected case")
        return
    }
    #expect(field == "qty")
    #expect(expected == "Int")
}
