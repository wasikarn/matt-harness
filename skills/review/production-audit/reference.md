# Production Audit — Reference

Worked example moved verbatim from SKILL.md (2026-08-23, 200-LOC cap refactor).

## Example

User:

```text
is this ready to ship?
```

Response:

```text
Production audit: 68/100, risky, because Stripe webhooks are verified but not idempotent and there is no rollback note for the pending migration.

Blockers:
- Add idempotency for `checkout.session.completed` before fulfilling orders.
- Write and test the rollback path for `20260511_add_billing_state.sql`.

High-value fixes:
- Add a health check that verifies database and payment-provider reachability.
- Add one E2E path for upgrade, webhook fulfillment, and billing-page refresh.

Evidence checked:
- `api/stripe/webhook.ts`
- `db/migrations/20260511_add_billing_state.sql`
- GitHub Actions run for the release branch

Next action: Want me to patch webhook idempotency first?
```
