# ``ServerCoreMCPVapor``

Host an authenticated, stateless local MCP endpoint with the official SDK transport.
Enable both the `MCP` and `Vapor` traits. Bind the hosting application to loopback and provision
an independent private machine credential. This endpoint does not implement delegated OAuth
for external AI clients. Every request uses a fresh SDK server and no session/SSE state.

## Topics

- ``ServiceMCPRoutes``
