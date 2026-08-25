---
name: grpc-node-patterns
description: "gRPC patterns for Node/Bun: proto, @grpc/grpc-js client/server, TypeScript codegen, streaming, deadlines/metadata. Use when building gRPC services in Node/Bun. Don't use for REST/HTTP or non-Node gRPC."
metadata:
  origin: kbg
model: inherit
effort: high
---

# gRPC Patterns for Node.js / Bun

## Pattern Map

Full code for every pattern below lives in `reference.md` — this file carries the trigger and
the decision rule; load the reference section when actually writing the code:

- **Proto definition** — proto3 service/message shapes, unary + server-stream + client-stream
  RPCs. `reference.md#proto-definition`.
- **TypeScript codegen** — `ts-proto` with `outputServices=grpc-js` for type-safe interfaces;
  preferred over hand-typing. `reference.md#typescript-codegen-recommended`.
- **Client setup** — create the client once at startup and reuse (it holds a connection pool);
  promisified unary call with deadline + metadata. `reference.md#client-setup`.
- **Without codegen** — `@grpc/proto-loader` with `keepCase: true` for simpler setups.
  `reference.md#without-codegen-proto-loader`.
- **Server** — implementation object, `callback(error, response)` convention, stream
  subscription with `cancelled` cleanup. `reference.md#server`.
- **Streaming** — consume with `data`/`end`/`error` events; treat `CANCELLED` as intentional.
  `reference.md#streaming-patterns`.
- **Deadlines and metadata** — always set a deadline; pass auth/trace metadata per call.
  `reference.md#deadlines-and-metadata`.
- **Health check** — standard gRPC health protocol via `grpc-health-check`; v2.x registers with
  `addToServer(server)`. `reference.md#health-check`.

## Error Codes

Use standard gRPC status codes — not HTTP codes (usage snippet: `reference.md#error-status-usage`):

| Code | Meaning | Use when |
|---|---|---|
| `OK` | Success | |
| `INVALID_ARGUMENT` | Bad input | Validation failure |
| `NOT_FOUND` | Resource missing | Entity doesn't exist |
| `ALREADY_EXISTS` | Duplicate | Create conflict |
| `PERMISSION_DENIED` | Unauthorized | Auth failure |
| `UNAUTHENTICATED` | No credentials | Missing token |
| `RESOURCE_EXHAUSTED` | Rate limited | Too many requests |
| `UNAVAILABLE` | Service down | Retry-able |
| `DEADLINE_EXCEEDED` | Timeout | Request took too long |
| `INTERNAL` | Server error | Unexpected failures |

## Bun Compatibility

`@grpc/grpc-js` mostly works on Bun with native Node.js imports, but the compatibility surface
is genuinely partial, not full — Bun's own compat docs mark `node:http2` (which grpc-js
depends on) at "95.25% of gRPC's test suite passes," not fully green, and there's a real
history of protocol-level bugs specific to this combination (malformed HTTP/2 frames breaking
Envoy, a compression-filter crash on single-file executables, missing trailers). Check the
current Bun version and open grpc-js/Bun issues before assuming it works unmodified,
especially for streaming or large messages. (`reference.md#bun-compatibility`.)

## Common Pitfalls

- **Create client once** — gRPC clients maintain a connection pool. Creating a new client per-request defeats the purpose. Create at startup and reuse.
- **Always set deadlines** — a gRPC call without a deadline will hang indefinitely if the server is unresponsive.
- **`callback(null, response)`** — the first argument to unary callbacks is the error (null on success). Don't call `callback(response)` — it treats the response as an error.
- **Proto field naming** — protobuf uses `snake_case`. Codegen (ts-proto/protobuf-ts) converts to `camelCase` by default (`image_data` → `imageData`). But proto-loader with `keepCase: true` (see `reference.md#without-codegen-proto-loader`) KEEPS `snake_case` — so the path you choose determines the field name.
- **Stream `cancel` vs `destroy`** — `stream.cancel()` sends a `CANCELLED` status to the server gracefully. `stream.destroy()` is a local-only teardown.
- **`UNAVAILABLE` is retryable** — implement exponential backoff for `UNAVAILABLE`. Retry `DEADLINE_EXCEEDED` only for idempotent operations — the deadline elapsed but the request may have completed server-side, so a blanket retry risks duplicates.

## Verify before use

1. Before applying, verify any pattern against @grpc/grpc-js's current docs.
   APIs drift across versions; if one has moved, the Common Pitfalls above name where each silently fails — never copy unverified, avoid drift by checking the changelog.
