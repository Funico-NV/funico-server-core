//
//  URL.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

extension URL {

    /// The WebSocket URL for this base URL, with the scheme derived rather than assumed.
    ///
    /// All three WebSocket modifiers in `funico-invoices-api` 1.2.5 build their URL by
    /// string-concatenating a hardcoded `ws://`. That works on a plain LAN address and
    /// breaks the moment anything sits behind TLS — a Cloudflare Tunnel, a reverse proxy,
    /// or the `https://` the agent will eventually serve.
    ///
    /// Returns `nil` for a scheme that is not one of `http`, `https`, `ws` or `wss`, rather
    /// than guessing.
    public var webSocketURL: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        case "ws", "wss": break
        default: return nil
        }

        return components.url
    }

    /// The WebSocket URL for a path under this base URL.
    ///
    /// ```swift
    /// URL(string: "https://box.tailnet.ts.net:5910")!.webSocketURL(path: "server", "state")
    /// // wss://box.tailnet.ts.net:5910/server/state
    /// ```
    public func webSocketURL(path components: String...) -> URL? {
        var url = self
        for component in components {
            url.appendPathComponent(component)
        }
        return url.webSocketURL
    }
}
