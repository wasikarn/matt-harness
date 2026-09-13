---
type: llm
focus: trace
---
`handle_stripe_webhook` has no dedup key or processed-event tracking — every delivery of the same
event (Stripe's own docs, quoted in the fixture, say redelivery happens even without our handler
failing) re-runs the full side effects, including `mailer.send_confirmation_email(order_id)`. A
customer could get the confirmation email multiple times, or worse side effects on webhooks that
aren't idempotent by nature. Score 1 if the report identifies the missing idempotency / dedup key
(e.g. tracking Stripe's event ID before processing) as a reliability gap that must be fixed before
enabling retries. Score 0 if it reviews the handler without flagging that redelivery causes
duplicate side effects.
