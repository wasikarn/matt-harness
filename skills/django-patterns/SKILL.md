---
name: django-patterns
description: Django architecture patterns, REST API design with DRF, ORM best practices, caching, signals, middleware, and production-grade Django apps.
metadata:
  origin: ECC
---

# Django Development Patterns

Production-grade Django architecture patterns for scalable, maintainable applications.

## When to Activate

- Building Django web applications
- Designing Django REST Framework APIs
- Working with Django ORM and models
- Setting up Django project structure
- Implementing caching, signals, middleware

## Project Structure

Use split settings (base, development, production, test) under `config/settings/` to manage environment-specific configuration without hardcoding secrets or debug flags. Place application logic in app-specific directories under `apps/` with models, views, serializers, and services co-located.

## Model Design Patterns

Extend `AbstractUser` for custom user models. Use `ForeignKey` with `related_name` for reverse relationships, `ManyToManyField` for many-to-many relations, and database `indexes` + `constraints` in Meta for performance and data integrity. Define custom `QuerySet` and `Manager` methods to encapsulate reusable query logic and avoid code duplication in views/services.

## Django REST Framework Patterns

Use `ModelSerializer` to handle automatic mapping of model fields to API responses. Override `get_serializer_class()` in ViewSets to return different serializers for different actions (e.g., create vs. retrieve). Implement custom field validation in `validate_field_name()` and cross-field validation in `validate()`. Use `@action` decorators on ViewSets for custom endpoints and `DjangoFilterBackend` + `filters.SearchFilter` for advanced filtering without boilerplate.

## Service Layer Pattern

Extract business logic (transactions, payments, emails) into service classes to keep views and models thin. Use `@transaction.atomic` to ensure multi-step operations succeed or fail together. Define static or instance methods on services to handle domain-specific workflows without mixing concerns.

## Caching Strategies

Cache at three levels: (1) view-level with `@cache_page` for entire responses, (2) template fragments with `{% cache %}` tag for expensive sections, (3) low-level with `cache.get()`/`cache.set()` for computed querysets. Always use namespaced cache keys to avoid collisions and invalidate on model saves via signals.

## Signals

Use `@receiver(post_save, sender=Model)` to trigger side effects (e.g., create related objects, invalidate cache, send notifications) after model saves. Import signals in `apps.py:ready()` to avoid import order issues.

## Performance Optimization

Prevent N+1 queries with `select_related()` for ForeignKey/OneToOne and `prefetch_related()` for ManyToMany/reverse ForeignKey. Add database indexes to frequently queried fields. Use `bulk_create()` and `bulk_update()` for large datasets instead of looping and saving.

## Live Docs

For current Django version syntax, ORM features, DRF integration patterns, and middleware docs, see [Django docs](https://docs.djangoproject.com/) via context7.

## Quick Reference

| Pattern | Description |
|---------|-------------|
| Split settings | Separate dev/prod/test settings |
| Custom QuerySet | Reusable query methods |
| Service Layer | Business logic separation |
| ViewSet | REST API endpoints |
| Serializer validation | Request/response transformation |
| select_related | Foreign key optimization |
| prefetch_related | Many-to-many optimization |
| Cache first | Cache expensive operations |
| Signals | Event-driven actions |
| Middleware | Request/response processing |

Remember: Django provides many shortcuts, but for production applications, structure and organization matter more than concise code. Build for maintainability.
