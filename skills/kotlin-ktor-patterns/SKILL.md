---
name: kotlin-ktor-patterns
description: Ktor server patterns including routing DSL, plugins, authentication, Koin DI, kotlinx.serialization, WebSockets, and testApplication testing. Use when building Ktor HTTP servers or writing Ktor plugins and tests. Don't use for non-Ktor Kotlin backends (see kbg:kotlin-patterns).
metadata:
  origin: ECC
---

# Ktor Server Patterns

Comprehensive Ktor patterns for building robust, maintainable HTTP servers with Kotlin coroutines.

## When to Activate

- Building Ktor HTTP servers
- Configuring Ktor plugins (Auth, CORS, ContentNegotiation, StatusPages)
- Implementing REST APIs with Ktor
- Setting up dependency injection with Koin
- Writing Ktor integration tests with testApplication
- Working with WebSockets in Ktor

## Route Organization: Public vs Protected Routes

```kotlin
fun Route.userRoutes() {
    route("/users") {
        // Public routes
        get { /* list users */ }
        get("/{id}") { /* get user */ }

        // Protected routes
        authenticate("jwt") {
            post { /* create user - requires auth */ }
            put("/{id}") { /* update user - requires auth */ }
            delete("/{id}") { /* delete user - requires auth */ }
        }
    }
}
```

Pattern: separate public endpoints from authenticated endpoints using `authenticate()` block scope.

## Core Concepts

**Routing DSL**: Ktor's routing uses Kotlin lambdas to define endpoints. Group related routes with `route()` and protect with `authenticate()`.

**Plugins**: Core features (auth, serialization, error handling, CORS) are installed as plugins on the Application.

**Koin Integration**: Use `by inject<T>()` to resolve dependencies in route handlers and services.

**Content Negotiation**: Configure kotlinx.serialization or Jackson for automatic request/response serialization with `ContentNegotiation` plugin.

**Error Handling**: Use `StatusPages` plugin to catch exceptions and format error responses consistently.

**WebSockets**: Install `WebSockets` plugin and define handlers with `webSocket("/path")` routes.

**Testing**: Use `testApplication { }` to spin up a test server with your actual application module; test with the Ktor test client.

## Live Docs

For current API details, configuration options, plugin setup, and version-specific guidance, consult [Ktor's official documentation](https://ktor.io/docs/). Use `/context7` within Claude Code for the latest framework docs and migration guides.

## Quick Reference: Ktor Patterns

| Pattern | Description |
|---------|-------------|
| `route("/path") { get { } }` | Route grouping with DSL |
| `call.receive<T>()` | Deserialize request body |
| `call.respond(status, body)` | Send response with status |
| `call.parameters["id"]` | Read path parameters |
| `call.request.queryParameters["q"]` | Read query parameters |
| `install(Plugin) { }` | Install and configure plugin |
| `authenticate("name") { }` | Protect routes with auth |
| `by inject<T>()` | Koin dependency injection |
| `testApplication { }` | Integration testing |

**Remember**: Ktor is designed around Kotlin coroutines and DSLs. Keep routes thin, push logic to services, and use Koin for dependency injection. Test with `testApplication` for full integration coverage.
