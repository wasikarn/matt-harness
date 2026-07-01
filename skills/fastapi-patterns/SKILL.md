---
name: fastapi-patterns
description: "FastAPI patterns: structure, Pydantic v2, dependency injection, async handlers, auth, service layers. Use when building FastAPI apps. Don't use for non-FastAPI backends (Flask/Django)."
metadata:
  origin: ECC
---

# FastAPI Patterns

Modern, production-grade FastAPI development: project layout, Pydantic v2 schemas, dependency injection, async patterns, auth, transactional service methods, and testing.

## Key Architectural Patterns

### Project Structure

Organize your app with these layers:
- **main.py** — App factory, lifespan management, middleware setup
- **config.py** — Settings via `pydantic-settings`, environment variables
- **dependencies.py** — Shared FastAPI dependency functions (DB sessions, auth)
- **routers/** — Endpoint handlers (thin, delegate to services)
- **models/** — SQLAlchemy ORM models
- **schemas/** — Pydantic v2 request/response schemas
- **services/** — Business logic, database mutations, transactions

### Dependency Injection & Type Aliases

Use `Annotated` type aliases to reduce repetition:

```python
DbDep = Annotated[AsyncSession, Depends(get_db)]
ActiveUserDep = Annotated[User, Depends(get_current_active_user)]
```

Then inject: `async def handler(db: DbDep, user: ActiveUserDep) → Response:`

### Async Database Sessions

Always use `async` SQLAlchemy execution—sync DB calls block the event loop. Set up graceful rollback on exception:

```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
```

### Service Layer Transactional Boundary

Move business logic and database mutations into a service class. Wrap mutations in try/except to catch `IntegrityError` and convert to domain exceptions. Rely on **atomic database constraints** (unique indexes, foreign keys) rather than application-level pre-checks—the former is race-safe:

> **Note on Database Design:** Application-level unique handling requires an underlying unique database index (e.g., `unique=True` on your SQLAlchemy mapping attributes). Without underlying constraints, application layer error-catching cannot safely prevent concurrent race conditions.

### Testing with httpx and pytest

Fixtures should:
- Override `app.dependency_overrides[get_db]` with an in-memory session
- Create a test client via `AsyncClient(transport=ASGITransport(app=app))`
- Provide reusable `registered_user` and `auth_token` fixtures for authenticated test cases

For current fixture patterns and latest pytest-asyncio usage, see the [FastAPI testing docs](https://fastapi.tiangolo.com/advanced/async-tests/).

---

## Live Docs

For Pydantic v2 schema details, async SQLAlchemy usage, and FastAPI middleware/dependency docs, use the context7 MCP tool.

## Anti-Patterns

```python
# Bad: business logic inside route handlers.
@router.post("/users/")
async def create_user(payload: UserCreate, db: DbDep):
    hashed = bcrypt.hash(payload.password)
    user = User(email=payload.email, hashed_password=hashed)
    db.add(user)
    await db.commit()
    return user

# Good: thin route, transactional service handling.
@router.post("/users/", response_model=UserResponse, status_code=201)
async def create_user(payload: UserCreate, db: DbDep):
    try:
        return await UserService(db).create(payload)
    except DuplicateUserError:
        raise HTTPException(status_code=400, detail="Email already registered")


# Bad: sync DB calls in async routes block the event loop.
@router.get("/items/")
async def list_items(db: Session = Depends(get_db)):
    return db.query(Item).all()

# Good: use async SQLAlchemy executions.
@router.get("/items/")
async def list_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Item))
    return result.scalars().all()
```

---

## Best Practices

- Always declare a typed `response_model` to prevent accidental PII/data leaks and output clean OpenAPI schemas.
- Consolidate standard middleware dependency injections via type-aliasing: `DbDep = Annotated[AsyncSession, Depends(get_db)]`.
- Wrap database mutation boundaries gracefully within transactions inside your service layer, catching structural database errors directly.
- Parse JWT parameters defensively, expecting potential string/integer cast mismatches from modern payload variations.
- Enforce deterministic sorting (e.g., `.order_by(Model.id)`) on all offset/limit paginated endpoints to avoid data skips.
- Isolate authorization checks from core authentication dependencies to provide precise REST status signals (`401` vs `403`).

## Verify before use

1. Before applying, verify any pattern against FastAPI's current docs.
   APIs drift across versions; if one has moved, the Anti-Patterns above name where each silently fails — never copy unverified, avoid drift by checking the changelog.
