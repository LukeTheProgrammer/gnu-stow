---
name: laravel-database-factory-definitions
description: What belongs in a model factory — a definition() that produces one valid row, and state methods only where two or more columns must move together. Single-column variation is the caller's job via create([...]). Use when writing or reviewing a factory in database/factories, when adding a state method, or when a test reaches for a factory helper.
---

# Factory definitions and states

A factory has exactly one job: produce a row that could have come out of the
application. Everything else a test needs is an override at the call site.

## The two-attribute rule

**A state method must set at least two attributes.** If it sets one, delete it and pass
an override instead.

```php
// ✗ a state that names one column's value
public function default(): static
{
    return $this->state(fn () => ['is_default' => true]);
}

// ✓ at the call site
Address::factory()->create(['is_default' => true]);
```

```php
// ✓ a state that holds several columns in agreement
public function onHold(OrderStatus $from = OrderStatus::PROCESSING): static
{
    return $this->state(fn () => [
        'status' => OrderStatus::ON_HOLD,
        'status_before_hold' => $from,
        'dispute_status' => 'needs_response',
    ]);
}
```

### Why the line sits there

A state exists to **enforce a relationship between columns**, not to name a single
column's value. Those are different jobs, and only the first one is impossible to do
correctly at the call site.

- **Multi-column states make invalid rows unspellable.** An order on hold with a null
  `status_before_hold` is a row the webhook handler cannot unwind. Written as an
  override array, every call site is a fresh chance to produce one; written as a state,
  the invariant has one home and no way around it. The same goes for `expired()` moving
  `starts_at` *and* `expires_at`, or `forPack()` fixing the six snapshot columns on an
  order item so they match the pack they were copied from.
- **A single-column state adds nothing but a second spelling.** `->default()` and
  `create(['is_default' => true])` are the same statement; one of them requires the
  reader to open the factory. Two ways to say one thing is a cost with no matching
  benefit.
- **The override is more honest about scope.** `create([...])` visibly applies to the
  row being made. A chain of one-column states reads like domain vocabulary and hides
  that it is just attribute assignment.

The count is the test because it is not a matter of taste. Two columns means there is a
rule between them; one column means there isn't.

## Computation follows the same rule

A state closure can see `$attributes` and compute from them — but that power only
justifies a state when it comes *with* a multi-column invariant.

```php
// ✓ derives one column from another, and sets both
public function refunded(?float $amount = null): static
{
    return $this->state(fn (array $attributes) => [
        'status' => OrderStatus::REFUNDED,
        'refunded_amount' => $amount ?? $attributes['total'],
    ]);
}
```

```php
// ✗ computation alone is not a reason for a state
public function discounted(): static
{
    return $this->state(fn (array $attributes) => [
        'price' => $attributes['price'] * 0.9,
    ]);
}
```

If one column needs a computed value, the caller has the value already — or can work it
out in the line above `create()`. Pushing that arithmetic into the factory buys nothing
and moves it away from the test that cares about the number.

## What `definition()` owes you

- **Every not-null column, with a value that could really occur.** A factory whose
  output fails a validator or a database constraint is not finished.
- **Related rows through nested factories** (`'product_id' => Product::factory()`), so
  a bare `create()` works with no setup.
- **Consistent foreign keys.** When two columns must point at the same parent, build the
  parent first and read both from it — never two independent nested factories:

  ```php
  // ✓ product_id and variant_id cannot disagree
  $variant = ProductVariant::factory()->create();

  return [
      'product_id' => $variant->product_id,
      'variant_id' => $variant->id,
      …
  ];
  ```
- **Nothing an observer already supplies.** `OrderFactory` omits `order_number` because
  `OrderObserver::creating()` mints it; duplicating the format lets the two drift.
- **The dullest valid row.** Default to `pending`, `is_active => true`, no coupon, no
  Stripe ids. Interesting rows are what states and overrides are for.

## Naming

- Name a state for the **domain condition** it creates — `guest()`, `expired()`,
  `orphaned()` — not for the column it writes.
- **Never override `Factory`'s own methods.** `for()`, `state()`, `count()`, `has()`
  are taken; a morph-subject setter is `forSubject()`, and redeclaring `for()` with a
  narrower signature is a fatal error, not a style problem.
- A state returns `static` and is pure: it stacks attributes and returns. Anything that
  writes to the database belongs in `definition()` or the caller.

## The check

```sh
# every state method, so you can count what each one sets
grep -rn -A6 'public function \w*(.*): static' database/factories/
```

For each hit, count the keys in the returned array. One key is this skill's bug.
