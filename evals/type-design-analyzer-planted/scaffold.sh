#!/usr/bin/env bash
mkdir -p src
cat > src/money.ts <<'FIXTURE_EOF'
export class Money {
  public amount: number;
  public currency: string;

  constructor(amount: number, currency: string) {
    this.amount = amount;
    this.currency = currency;
  }

  add(other: Money): Money {
    return new Money(this.amount + other.amount, this.currency);
  }
}
FIXTURE_EOF
