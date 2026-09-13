#!/usr/bin/env bash
mkdir -p src
cat > src/money.ts <<'FIXTURE_EOF'
export type CurrencyCode = "USD" | "EUR" | "THB";

export class Money {
  private constructor(
    public readonly cents: number,
    public readonly currency: CurrencyCode,
  ) {}

  static of(cents: number, currency: CurrencyCode): Money {
    if (!Number.isInteger(cents)) throw new RangeError("cents must be an integer");
    return new Money(cents, currency);
  }

  add(other: Money): Money {
    if (other.currency !== this.currency) {
      throw new TypeError(`currency mismatch: ${this.currency} vs ${other.currency}`);
    }
    return new Money(this.cents + other.cents, this.currency);
  }
}
FIXTURE_EOF
