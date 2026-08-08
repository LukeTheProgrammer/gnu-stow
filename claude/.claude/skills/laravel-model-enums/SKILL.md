---
name: laravel-model-enums
description: How a model expresses a fixed set of values — a string-backed enum in app/Enums rather than a run of class constants — plus the casing and house style for those enums. Use when adding or editing an enum, adding a class constant to a model, or adding a status/type/action/role column.
---

# Model enums

## A list of constants is an enum

When a model declares constants that are **alternatives to each other** — the set of
values one column is allowed to hold — that set is a string-backed enum in
`app/Enums`, not a run of `const` declarations.

```php
// ✗ the model
class ActivityLog extends Model
{
    public const ORDER_STATUS_CHANGED = 'order.status_changed';
    public const ORDER_CANCELLED = 'order.cancelled';
    public const USER_ROLE_GRANTED = 'user.role_granted';
    public const USER_ROLE_REVOKED = 'user.role_revoked';
    // …
}
```

```php
// ✓ app/Enums/ActivityAction.php
enum ActivityAction: string
{
    case ORDER_STATUS_CHANGED = 'order.status_changed';
    case ORDER_CANCELLED = 'order.cancelled';
    case USER_ROLE_GRANTED = 'user.role_granted';
    case USER_ROLE_REVOKED = 'user.role_revoked';
}
```

```php
// ✓ the model casts it, and stops carrying the list
protected function casts(): array
{
    return ['action' => ActivityAction::class];
}
```

### Why

A constant is a name for one value. A *list* of constants is a type — the column
accepts these values and no others — and PHP has a construct for that which the
constants cannot imitate:

- **The type is checkable.** `logActivity(ActivityAction $action)` cannot be handed
  `'oder.cancelled'`. With constants the parameter is `string`, every typo is a
  runtime discovery, and nothing stops a caller passing a bare literal that skips the
  constants entirely.
- **The set is enumerable.** `ActivityAction::cases()` gives validation rules
  (`Rule::enum(...)`), filter dropdowns, and exhaustive `match` for free. A list of
  constants can only be enumerated by hand, in a second place that goes stale.
- **Behavior has somewhere to live.** `label()`, `isTerminal()`, `allowedTransitions()`
  attach to the value itself instead of becoming `match` blocks scattered across
  services and resources.
- **Eloquent casts it.** Reads and writes convert at the model boundary, so the typed
  value flows through the app and the string exists only in the database.

### One enum per column, not per prefix

Group by **the column the values live in**, not by the name they start with. Constants
prefixed `ORDER_*` and `USER_*` that all write to the same `action` column are one
enum, and the prefix belongs in the *value* (`'order.cancelled'`), which is what makes
it sortable and greppable. Splitting them into `OrderAction` and `UserAction` gives
the column two types, so nothing can type-hint it and every call site unions them back
together.

Conversely, two constants that happen to share a prefix but write to different columns
are two enums.

### Enumerate lifecycle, not business events

An enum is the right shape only for a set that is **closed**. Before writing the
cases, ask what makes the set stop growing — and if the honest answer is "it doesn't",
the set is wrong, not the enum.

Audit trails are where this goes wrong first. A column of business events
(`'order.cancelled'`, `'order.confirmation_resent'`, `'user.role_granted'`) grows a
case for every admin action ever added, and each one costs a case, a label in the
frontend, and a migration when the column is constrained. The four lifecycle verbs do
not grow:

```php
enum ActivityAction: string
{
    case CREATED = 'created';
    case UPDATED = 'updated';
    case DELETED = 'deleted';
    case RESTORED = 'restored';
}
```

Nothing is lost, because the entry already records what happened: the **subject** says
which model and the **old/new values** say which fields moved and where to. "Cancelled"
is an update whose `status` went to `cancelled` — storing that as its own action name
duplicates the diff sitting next to it, and the two can disagree.

For an event with nothing stored to diff (a confirmation email resent, a failed refund
attempt), put a **self-describing key in the values** rather than inventing an action:

```php
$order->logActivity(ActivityAction::UPDATED, [], ['confirmation_resent_to' => $email]);
$order->logActivity(ActivityAction::UPDATED, [], ['refund_error' => $message]);
```

Queries that used to filter on the action then filter on the key
(`whereNotNull('new_values->confirmation_resent_to')`), which is the same lookup
against a column that is not carrying a taxonomy.

The general test: if adding a feature would add a case, the enum is a log of features,
not a type. Statuses, lifecycle verbs, and payment types are closed. Business events
are not.

### What stays a constant

Not every `const` is an enum candidate. A constant that is **a single scalar with no
alternatives** is correctly a constant:

```php
public const RESERVATION_MINUTES = 15;   // ✓ a tunable number
public const SHIPPING_TAX_CODE = 'txcd_92010001';  // ✓ one external identifier
```

The test is whether the values are *mutually exclusive choices for the same slot*. Two
unrelated magic numbers on one model are not a set. One value that a column must be
one of, with more to come, is.

### Applying it to an existing model

1. Create the enum in `app/Enums`, values **identical** to the old constant values —
   the database is full of those strings and this is not a data migration.
2. Cast the column in the model; delete the constants.
3. Replace `Model::CONST` at call sites with `Enum::CASE`, and type-hint the enum
   wherever the value is a parameter.
4. Comparisons become `===` on the enum; `whereIn`-style queries take
   `array_column(Enum::cases(), 'value')` or the enum instances directly.
5. Widen validation to `Rule::enum(Enum::class)`.

Watch for values compared as raw strings in Blade, Inertia props, or JSON resources —
those are the ones the compiler cannot find for you. A cast column arrives in a
resource as the enum; call `->value` explicitly when the frontend expects the string.

## House style for the enums themselves

- Backed by `string`, never `int` — the database column stays readable, and a
  reordered enum cannot silently remap existing rows.
- **Case names are `UPPER_CASE`; values are the same word in `snake_case`.**

  ```php
  case FREE_SHIPPING = 'free_shipping';   // ✓
  case free_shipping = 'free_shipping';   // ✗
  ```

  The case is a constant and reads like one at the call site
  (`CouponType::FREE_SHIPPING`), which sets it apart from a method or property on
  sight. The value is what lands in the database and in JSON, where `snake_case`
  matches every other column and payload key. The two still mirror each other
  exactly, so neither has to be looked up to know the other.
- A `label(): string` returning human text, and `labels(): array` keyed by value when
  the set feeds a dropdown. Human text does not belong in the value.
- Behavior that answers a question about the value (`isTerminal()`,
  `allowedTransitions()`) lives on the enum. Behavior that touches other models does
  not — that is the service's job.
- Use `match` on the enum rather than `switch` on the value: it is exhaustive, so
  adding a case surfaces every place that must handle it.
