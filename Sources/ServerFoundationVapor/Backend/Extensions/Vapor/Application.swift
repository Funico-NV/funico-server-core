//
//  ServerStateHolder.swift
//  funico-server-foundation
//
//  Created by Damian Van de Kauter on 04/02/2026.
//

import Vapor

extension Application {
    
    /// Exposes OpenAPI documentation routes in the application.
    ///
    /// This method creates two HTTP GET endpoints for serving OpenAPI documentation:
    ///
    /// - `/api/{openapiFile}`: Serves the raw OpenAPI specification file (e.g., YAML or JSON) from the specified bundle.
    ///   - If the file is not found in the bundle or does not exist on disk, responds with a `404 Not Found` and an error message.
    ///   - If the file exists, streams the file with the appropriate media type.
    ///   - If streaming fails, responds with a `500 Internal Server Error` and logs the error.
    ///
    /// - `/api/docs`: Serves a simple HTML page rendering the API documentation using Swagger UI, configured to load the OpenAPI specification from `/api/{openapiFile}`.
    ///
    /// - Parameters:
    ///   - openapiFile: The name of the OpenAPI specification file (without extension) to serve. Defaults to `"openapi"`.
    ///   - openapiExtension: The file extension (e.g., `"yaml"` or `"json"`) of the OpenAPI specification. Defaults to `"yaml"`.
    ///   - bundle: The app bundle containing the OpenAPI specification file.
    ///
    /// - Important:
    ///   Ensure the OpenAPI specification file is included in your target’s
    ///   resources in `Package.swift`. Otherwise, it will not be bundled
    ///   with the executable and cannot be loaded at runtime.
    ///
    ///   *It might be necessary to clean the build folder after adding the resource.*
    ///
    ///   ### Example:
    ///   ```swift
    ///   .target(
    ///       name: "YourTarget",
    ///       resources: [
    ///           .copy("openapi.yaml")
    ///       ]
    ///   )
    ///   ```
    public func exposeDocumentation(file openapiFile: String = "openapi", extension openapiExtension: String = "yaml", in bundle: Bundle) {
        get("api", "\(openapiFile)") { req async throws -> Response in
            guard let url = bundle.url(forResource: openapiFile, withExtension: openapiExtension) else {
                var headers = HTTPHeaders()
                headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
                let message = """
                OpenAPI specification not found in the app bundle.
                """
                return Response(status: .notFound, headers: headers, body: .init(string: message))
            }

            let path = url.path
            let fm = FileManager.default
            guard fm.fileExists(atPath: path) else {
                var headers = HTTPHeaders()
                headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
                let message = """
                OpenAPI specification URL resolved, but file does not exist on disk.

                Resolved path: \(path)
                """
                return Response(status: .notFound, headers: headers, body: .init(string: message))
            }

            do {
                return try await req.fileio.asyncStreamFile(at: path, mediaType: .init(type: "application", subType: openapiExtension))
            } catch {
                req.logger.error("Failed to stream OpenAPI spec: \(error)")
                
                var headers = HTTPHeaders()
                headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
                let message = """
                Failed to stream the bundled OpenAPI specification.

                Resolved path: \(path)
                Error: \(error)
                """
                return Response(status: .internalServerError, headers: headers, body: .init(string: message))
            }
        }
        
        get("api", "docs") { req -> Response in
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset=\"utf-8\" />
              <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
              <title>API Docs</title>
              <link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui.css\" />
              <style>html, body, #swagger-ui { height: 100%; margin: 0; }</style>
            </head>
            <body>
              <div id=\"swagger-ui\"></div>
              <script src=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>
              <script>
                window.onload = () => {
                  window.ui = SwaggerUIBundle({
                    url: '/api/\(openapiFile)',
                    dom_id: '#swagger-ui',
                    deepLinking: true,
                    presets: [SwaggerUIBundle.presets.apis],
                  });
                };
              </script>
            </body>
            </html>
            """
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
            return Response(status: .ok, headers: headers, body: .init(string: html))
        }
    }
}
