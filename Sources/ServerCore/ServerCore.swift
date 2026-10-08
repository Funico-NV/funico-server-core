//
//  ServerCore.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 26/12/2025.
//

// The dependency-free core: `APIModel`, `APIModelError`, `Query` and `SQLQuery`.
//
// Nothing in this target may import Vapor, or the iOS app and the agent can no
// longer depend on it. That constraint is the entire point of the 2.0 split.
