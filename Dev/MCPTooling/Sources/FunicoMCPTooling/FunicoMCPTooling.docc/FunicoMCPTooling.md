# ``FunicoMCPTooling``

Pair service behavior with standard MCP definitions, then use the same catalog for discovery and calls.

## Overview

This standalone development package uses the official Swift SDK. Construct each ``ServiceTool``
with an SDK `Tool` definition and an argument-validating handler. ``ServiceToolRegistry`` creates
an SDK `Server` with the standard tool handlers. The caller manages its transport and lifetime.

The included demo uses only an in-memory transport and a read-only fixture. HTTP hosting,
authorization, schema validation, the Agent relay and generated Manager forms are later steps.
Neither tool descriptions nor annotations grant permissions.

## Topics

### Register service behavior

- ``ServiceTool``
- ``ServiceTool/definition``
- ``ServiceTool/init(definition:invoke:)``

### Discover and invoke

- ``ServiceToolRegistry``
- ``ServiceToolRegistry/tools``
- ``ServiceToolRegistry/init(_:)``
- ``ServiceToolRegistry/makeServer(name:version:)``
- ``ServiceToolRegistry/RegistrationError``
