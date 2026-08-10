//
//  AgentControlPayloads.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

#if Vapor
import Foundation
import Vapor
import ServerFoundationCore

// The payload types themselves live in Core, so the agent can parse them without linking Vapor.
// What belongs here is only the part that is genuinely Vapor's: teaching them to be response
// bodies.

extension ServerJobStatus: Content {}
extension ControlHealth: Content {}
extension ControlState: Content {}
extension ServerJobDescriptor: Content {}
#endif
