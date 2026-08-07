//
//  Query.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 26/12/2025.
//

public struct Query {
    
    public let sql: String
    
    public init(sql: String) {
        self.sql = sql
    }
}

extension Query: Sendable {}

extension Query: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    
    public typealias StringLiteralType = String
    public typealias StringInterpolation = Query.QueryStringInterpolation
    
    public struct QueryStringInterpolation: StringInterpolationProtocol {
        public var result: String = ""
        
        public init(literalCapacity: Int, interpolationCount: Int) {
            result.reserveCapacity(literalCapacity)
        }
        public mutating func appendLiteral(_ literal: String) {
            result.append(literal)
        }
        public mutating func appendInterpolation(_ value: String) {
            result.append(value)
        }
        public mutating func appendLiteral(_ query: Query) {
            result.append(query.sql)
        }
        public mutating func appendInterpolation(_ query: Query) {
            result.append(query.sql)
        }
    }
    
    public init(stringLiteral value: String) {
        self.init(sql: value)
    }

    public init(stringInterpolation: Query.StringInterpolation) {
        self.init(sql: stringInterpolation.result)
    }
}
