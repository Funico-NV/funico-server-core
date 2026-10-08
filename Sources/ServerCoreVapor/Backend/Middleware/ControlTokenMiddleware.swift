//
//  ControlTokenMiddleware.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

#if Vapor
import Foundation
import Vapor

/// Requires `Authorization: Bearer <token>` on every control route.
///
/// The listener is on loopback, but loopback is not a trust boundary: any process running as the
/// same user can connect to `127.0.0.1:<port>`, and one of the routes shuts the server down. The
/// token is doing real work.
///
/// **The tradeoff, stated plainly.** On Linux `/proc/<pid>/environ` is `0400` owner-only, and on
/// macOS `ps -E` needs same-user or root, so the token is not readable across users — but a
/// same-user process can read it. A `0600` Unix domain socket would be strictly tighter on Unix.
/// That tightness is what is being traded for Windows parity, where SwiftNIO's UDS support is
/// unverified and Vapor's server configuration is hostname/port-shaped.
public struct ControlTokenMiddleware: AsyncMiddleware {

    private let token: [UInt8]

    public init(token: String) {
        self.token = Array(token.utf8)
    }

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let presented = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing bearer token")
        }

        // Constant time. A byte-by-byte `==` leaks the length of the matching prefix, which is
        // enough to recover the token one byte at a time against a local listener.
        guard Array(presented.utf8).secureCompare(to: token) else {
            throw Abort(.unauthorized, reason: "Invalid bearer token")
        }

        return try await next.respond(to: request)
    }
}
#endif
