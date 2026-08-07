//
//  APIModel+Error.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 26/12/2025.
//

public enum APIModelError: Swift.Error {
    
    case missingField(_ fieldName: String)
    case invalidFieldType(_ fieldName: String, expectedType: String)
}
