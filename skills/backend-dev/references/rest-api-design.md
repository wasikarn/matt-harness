---
title: REST API Design (Microsoft Learn)
type: reference
tags:
  - rest
  - api
  - http
  - design
  - best-practice
  - microsoft-learn
sources:
  - https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design
related:
  - rest-api-bandwidth-optimization
created: 2026-06-03
updated: 2026-06-03
---

# REST API Design (Microsoft Learn)

Synthesized from [Azure Architecture Center — Web API Design Best Practices](https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design) (2026-03-06 update). Compresses 6,682 words into the rules that actually shape an API contract. Not a substitute for the full article — see the source for worked examples, headers, and edge cases.

## Core Principles

- **Platform independence** — HTTP as the contract, JSON (or XML) as the wire format, clear docs as the surface. Clients shouldn't care about your internal implementation.
- **Loose coupling** — client and service evolve independently. Agree on wire format, never internal schema.
- **Statelessness** — each request is atomic; no transient state between requests. Scalability wins, storage back-pressure wins differently.
- **Uniform interface** — HTTP verbs carry the operation. URIs carry the resource. Don't smuggle verbs into the path.

## URI Design

| Rule | Good | Avoid |
|------|------|-------|
| Nouns, not verbs | `/orders` | `/create-order` |
| Plural for collections | `/customers`, `/customers/5` | `/customer` |
| Max depth: collection/item/collection | `/customers/1/orders` | `/customers/1/orders/99/products` |
| Mirror business entities, not DB tables | `/orders` (with mapping layer) | `/orders_table` |

**Relations:** prefer including a HATEOAS link in the body over deep-nested paths — they survive schema refactors. If you must nest, cap at *collection/item/collection*.

**Non-resource operations** (calculator, search): use query strings on a verb-named URI, e.g. `GET /add?operand1=99&operand2=1`. Use sparingly.

## HTTP Methods

| Method | On collection `/customers` | On item `/customers/1` | Notes |
|--------|---------------------------|------------------------|-------|
| GET | retrieve all | retrieve one | Safe, cacheable. Returns 200/204/404 |
| POST | create new (server assigns URI) | error 400/405 | Idempotency NOT guaranteed |
| PUT | bulk update | replace or create | **Idempotent** — same body → same result. Body = full representation |
| PATCH | bulk partial update | partial update | Body = patch doc (RFC 5789). See formats below |
| DELETE | remove all | remove one | Returns 204 or 404 |

**Critical:** PUT must be idempotent. POST creates (server assigns URI in `Location` header → 201). PATCH/POST are not guaranteed idempotent — design retries carefully.

### PATCH formats

| Format | Media type | Use when |
|--------|------------|----------|
| JSON merge patch | `application/merge-patch+json` (RFC 7396) | Simpler. `null` deletes a field. Avoid if resource has explicit null values |
| JSON patch (RFC 6902) | `application/json-patch+json` | Need ordered ops: add/remove/replace/copy/test. More flexible |

## Status Codes — minimums to remember

| Code | When |
|------|------|
| 200 OK | Success with body |
| 201 Created | POST/PUT created resource; `Location` header points to new URI |
| 202 Accepted | Async started; `Location` points to status endpoint |
| 204 No Content | Success, no body (DELETE, partial updates) |
| 303 See Other | Async completed; follow `Location` to new resource |
| 304 Not Modified | Caching |
| 400 Bad Request | Malformed/invalid input |
| 404 Not Found | Resource missing |
| 405 Method Not Allowed | Verb not supported on this URI |
| 406 Not Acceptable | `Accept` header unmatched |
| 409 Conflict | State collision (optimistic concurrency, version mismatch) |
| 415 Unsupported Media Type | `Content-Type` or patch format unsupported |
| 429 Too Many Requests | Rate limiting |

## Content Negotiation

- `Content-Type` on requests/responses = the wire format (`application/json` is the default for modern APIs).
- `Accept` on requests = client's preferred formats. If server can't match → 406.
- If server doesn't support the request's `Content-Type` → 415.

## Asynchronous Operations

Long-running POST/PUT/PATCH/DELETE → return **202 Accepted** with a status endpoint in `Location`. The status endpoint:

1. Polls via GET — return current state, ETA, optional cancel link.
2. On completion — return **303 See Other** with the new resource's URI in `Location`.

## Pagination, Filtering, Sorting, Projection

| Feature | Query param | Example | Note |
|---------|-------------|---------|------|
| Pagination | `limit` + `offset` | `?limit=25&offset=50` | Cap `max-limit` to prevent DoS |
| Filtering | arbitrary params | `?minCost=100&status=shipped` | Validate per resource |
| Sorting | `sort` | `?sort=price` | Hurts cache hit rate |
| Field projection | `fields` | `?fields=id,name` | Validate field allowlist |

**Cache gotcha:** `sort` and `fields` change the URI key — if you cache by URL, every combination is a separate cache entry. Plan for cache-key cardinality.

## Partial Responses (large binary)

- `Accept-Ranges: bytes` on GET for large resources.
- Client uses `Range: bytes=0-2499` → server returns **206 Partial Content** with `Content-Range`.
- HEAD first to learn `Content-Length` before chunking.

## HATEOAS

Each representation includes `links: [{rel, href, action, types}]` so clients can navigate without prior URI knowledge. No general standard — Microsoft Learn's example uses `rel` + `href` + HTTP `action` + `types[]`. Including `self` is mandatory for each resource.

**Trade-off:** HATEOAS complicates versioning (every link carries the version signal). Skip if the consumer is a closed internal system where URI schemas are stable.

## Versioning

| Strategy | Pros | Cons |
|----------|------|------|
| No versioning | Simple, internal-only | Breaking changes break clients |
| URI: `/v2/customers/3` | Cache-friendly, explicit | URI purists object; complicates HATEOAS |
| Query: `?version=2` | Same resource, same URI | Some proxies don't cache query-string URIs; HATEOAS still needs the param |
| Custom header: `Custom-Header: api-version=1` | Clean URIs | Custom parsing; cache fragmentation |
| Media type: `Accept: application/vnd.contoso.v1+json` | Best for HATEOAS (link carries its own version) | Most complex; same cache-fragmentation risk |

**Rule of thumb:** public/external API with multiple client types → media type or header. Internal single-team API → no versioning until you actually break something.

## Multitenancy

Common tenant-isolation strategies:

1. **DNS subdomain** — `acme.api.contoso.com/orders/3`. Preserve hostname through proxies to avoid URL rewrite leaks.
2. **HTTP header** — one of three forms:
   - Custom header: `X-Tenant-ID: acme` or `X-Organization-ID: acme`
   - Host-based: standard `Host` or `X-Forwarded-Host` header
   - JWT claim: extracted from `Authorization: Bearer <token>`

   Requires L7 gateway. **Caching risk:** URI-only cache keys leak across tenants unless cache also indexes the header.
3. **URI path** — `/tenants/acme/orders/3`. Effective but compromises RESTful design and requires complex routing (regex/pattern matching) to canonicalize the path.

## Distributed Tracing

Propagate `Correlation-ID`, `X-Request-ID`, or `X-Trace-ID` headers. Return the same ID in the response. These enable end-to-end visibility, rapid failure identification, latency monitoring, and dependency mapping across services.

## Richardson Maturity Model

| Level | Definition | Real-world |
|-------|------------|------------|
| 0 | One URI, POST for everything | SOAP |
| 1 | One URI per resource | Many "REST" APIs |
| 2 | HTTP verbs on resources | Most "REST" APIs today |
| 3 | HATEOAS | Rarely worth the complexity |

Most production APIs sit at Level 2. Level 3 has marginal value unless your API is public, large, and consumed by many clients you don't control.

## OpenAPI / Contract-First

Adopt OpenAPI for:
- Generating client libraries (Swagger codegen, OpenAPI Generator).
- Keeping docs in sync with the actual contract.
- Contract-first development: design the spec → stub the server → implement.

The OpenAPI guidelines are opinionated — they'll push you toward conventions (plural nouns, ISO 8601 dates, snake_case vs camelCase rules). Conforming beats custom unless you have a real reason.

## Cross-Reference

- [[rest-api-bandwidth-optimization]] — field projection, nested inclusion, partial responses (overlaps with the Projection & Partial Responses sections above)

## Source

- Azure Architecture Center — [Web API Design Best Practices](https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design) (Microsoft Learn, 2026-03-06, 6,682 words)
- Synthesized: 2026-06-03, ~1,200 words
