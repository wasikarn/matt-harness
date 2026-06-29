---
name: springboot-patterns
description: Spring Boot architecture patterns, REST API design, layered services, data access, caching, async processing, and logging. Use for Java Spring Boot backend work.
metadata:
  origin: ECC
---

# Spring Boot Development Patterns

Spring Boot architecture and API patterns for scalable, production-grade services.

## When to Activate

- Building REST APIs with Spring MVC or WebFlux
- Structuring controller → service → repository layers
- Configuring Spring Data JPA, caching, or async processing
- Adding validation, exception handling, or pagination
- Setting up profiles for dev/staging/production environments
- Implementing event-driven patterns with Spring Events or Kafka

## Live Docs

For current annotation syntax, configuration properties, and API details, refer to the [Spring Boot documentation](https://spring.io/projects/spring-boot) via context7.

## API Layer

Use `@RestController` with constructor injection, `@Valid` on request bodies, and `ResponseEntity` for status codes. Prefer DTOs (`record` classes) with `@NotBlank`, `@NotNull`, and JSR-303 validators. Centralize validation errors via `@ControllerAdvice` handlers.

## Repository & Transactions

Use Spring Data JPA with `@Query` for custom methods. Annotate write operations with `@Transactional`; use `@Transactional(readOnly = true)` for queries to hint the JPA provider.

## Caching & Async

- **Caching**: Requires `@EnableCaching`. Use `@Cacheable(value = "...", key = "#id")` for reads, `@CacheEvict` for invalidation.
- **Async**: Requires `@EnableAsync`. Mark methods `@Async` and return `CompletableFuture<T>` for non-blocking execution.

## Logging & Observability

Use SLF4J + Logback. Include structured context (e.g., `methodName marketId={} status={}`). Avoid logging sensitive data.

## Rate Limiting

Use Bucket4j or similar library in a filter. **Security Note**: `X-Forwarded-For` is spoofable by clients. Only trust it when:
1. Your app is behind a **trusted reverse proxy** (nginx, AWS ALB, etc.)
2. You have registered `ForwardedHeaderFilter` or set `server.forward-headers-strategy=NATIVE/FRAMEWORK`
3. Your proxy **overwrites** (not appends to) the `X-Forwarded-For` header
4. You configured `server.tomcat.remoteip.trusted-proxies` or equivalent

Without this setup, use `request.getRemoteAddr()` directly (the immediate connection IP). Never read `X-Forwarded-For` headers directly without proper proxy configuration.

## Background Jobs

Use Spring’s `@Scheduled` or integrate with queues (e.g., Kafka, SQS, RabbitMQ). Keep handlers idempotent and observable.

## Observability

- Structured logging (JSON) via Logback encoder
- Metrics: Micrometer + Prometheus/OTel
- Tracing: Micrometer Tracing with OpenTelemetry or Brave backend

## Production Defaults

- Prefer constructor injection, avoid field injection
- Enable `spring.mvc.problemdetails.enabled=true` for RFC 7807 errors (Spring Boot 3+)
- Configure HikariCP pool sizes for workload, set timeouts
- Use `@Transactional(readOnly = true)` for queries
- Enforce null-safety via `@NonNull` and `Optional` where appropriate

**Remember**: Keep controllers thin, services focused, repositories simple, and errors handled centrally. Optimize for maintainability and testability.
