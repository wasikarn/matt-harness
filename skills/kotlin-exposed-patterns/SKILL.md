---
name: kotlin-exposed-patterns
description: JetBrains Exposed ORM patterns including DSL queries, DAO pattern, transactions, HikariCP connection pooling, Flyway migrations, and repository pattern. Use when building database access with Exposed in Kotlin. Don't use for non-Kotlin ORMs or non-Exposed DB access.
metadata:
  origin: ECC
---

# Kotlin Exposed Patterns

Comprehensive patterns for database access with JetBrains Exposed ORM, including DSL queries, DAO, transactions, and production-ready configuration.

## When to Use

- Setting up database access with Exposed
- Writing SQL queries using Exposed DSL or DAO
- Configuring connection pooling with HikariCP
- Creating database migrations with Flyway
- Implementing the repository pattern with Exposed
- Handling JSON columns and complex queries

## How It Works

Exposed provides two query styles: DSL for direct SQL-like expressions and DAO for entity lifecycle management. HikariCP manages a pool of reusable database connections configured via `HikariConfig`. Flyway runs versioned SQL migration scripts at startup to keep the schema in sync. All database operations run inside `newSuspendedTransaction` blocks for coroutine safety and atomicity. The repository pattern wraps Exposed queries behind an interface so business logic stays decoupled from the data layer and tests can use an in-memory H2 database.

## Quick Start

For current API syntax, versions, and configuration, see [Exposed official docs](https://jetbrains.github.io/Exposed/) via context7.

**Key patterns:**
- **DSL style**: Direct SQL-like table queries (`UsersTable.selectAll().where { }`)  
- **DAO style**: Entity lifecycle management with `UserEntity.new { }` and relationships
- **Coroutine safety**: Always use `newSuspendedTransaction` for async database operations
- **Connection pooling**: Configure HikariCP with `maximumPoolSize`, `transactionIsolation`, and validation
- **Migrations**: Flyway runs versioned SQL scripts from `src/main/resources/db/migration/` at startup
- **Repository pattern**: Wrap Exposed queries behind interfaces for testability and decoupling from business logic

## Quick Reference: Exposed Patterns

| Pattern | Description |
|---------|-------------|
| `object Table : UUIDTable("name")` | Define table with UUID primary key |
| `newSuspendedTransaction { }` | Coroutine-safe transaction block |
| `Table.selectAll().where { }` | Query with conditions |
| `Table.insertAndGetId { }` | Insert and return generated ID |
| `Table.update({ condition }) { }` | Update matching rows |
| `Table.deleteWhere { }` | Delete matching rows |
| `Table.batchInsert(items) { }` | Efficient bulk insert |
| `innerJoin` / `leftJoin` | Join tables |
| `orderBy` / `limit` / `offset` | Sort and paginate |
| `count()` / `sum()` / `avg()` | Aggregation functions |

**Remember**: Use the DSL style for simple queries and the DAO style when you need entity lifecycle management. Always use `newSuspendedTransaction` for coroutine support, and wrap database operations behind a repository interface for testability.
