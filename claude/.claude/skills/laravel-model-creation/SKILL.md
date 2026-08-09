---
name: laravel-model-creation
description: How model rows get created — always through a query helper (create, firstOrCreate, updateOrCreate, or a relation's create), never `new Model()` followed by `save()` — and why a model must never carry a method that creates instances of itself. Use when writing code that persists a new record, or when adding a method to a model that returns a new instance of that model.
---

# Creating models

## Create through a helper, not `new` + `save()`

```php
// ✗
$order = new Order();
$order->user_id = $user->id;
$order->total = $total;
$order->save();
```

```php
// ✓
$order = Order::create([
    'user_id' => $user->id,
    'total' => $total,
]);
```

The helpers, by intent:

| Intent | Use |
|---|---|
| Always a new row | `Model::create([...])` |
| One row per key, create if missing | `Model::firstOrCreate([$key], [$extra])` |
| One row per key, overwrite if present | `Model::updateOrCreate([$key], [$values])` |
| Belongs to a parent | `$parent->children()->create([...])` |
| Many at once | `$parent->children()->createMany([...])` |

### Why

- **Mass-assignment protection only applies to the helpers.** `#[Fillable]` guards
  `create()` and `fill()`; assigning `$model->column = …` bypasses it completely. The
  `new` form doesn't just skip the check — it removes the guard from precisely the
  code paths that write user input.
- **One statement, one point of failure.** A run of assignments can be half-applied by
  an early return or a throw, leaving a partially-built model that later code treats
  as real.
- **Events fire once, with the whole row.** `creating`/`created` observers and
  `booted()` hooks see complete attributes. With staged assignment the ordering
  becomes something callers have to know about.
- **`firstOrCreate` / `updateOrCreate` state the invariant.** "One cart per session"
  is one call; the `find`-then-`new`-then-`save` version is three statements that read
  as fine and race under concurrency.

### Prefer the relation when there is a parent

```php
$order->items()->create([...]);            // ✓ foreign key cannot be wrong
OrderItem::create(['order_id' => $order->id, ...]);  // ✗ works until someone passes the wrong id
```

### When `new` + `save()` is genuinely necessary

Rare, and each case should say why in a comment:

- The instance is needed **before** it is persisted — to pass to something that
  computes a value from it. Prefer `Model::make([...])` (unsaved, still respects
  fillable) and persist with `->save()` at the end.
- A column is **guarded on purpose** and must still be written — use one
  `forceFill([...])->save()` statement rather than a run of assignments.

Whatever the reason, keep it to one `fill`/`forceFill` call plus `save()`. A column-by-column
build-up is never the necessary part.

## Updating: `update()`, not `save()`

The same rule applies to a row that already exists. Assign-then-`save()` is the update
form of the same bug.

```php
// ✗
$user->fill($data);
$user->save();

// ✗
$user->name = $data['name'];
$user->email = $data['email'];
$user->save();
```

```php
// ✓
$user->update($data);
```

Conditional fields go into the array, not into a run of `if`s around assignments:

```php
$updates = Arr::only($data, ['name', 'email', 'phone']);

if (! empty($data['password'])) {
    $updates['password'] = $data['password'];
}

$user->update($updates);
```

`update()` is `fill()` plus `save()` in one call, so it honours `#[Fillable]`, returns
a bool you can act on, and leaves no window where the in-memory model disagrees with
the row.

### When `save()` is genuinely necessary for an update

**Writing a column that is not fillable.** `update()` silently drops keys outside
`#[Fillable]` — that is the guard working, so do not widen the attribute to get around
it. Assign the columns **directly**, then `save()`, with a comment saying why:

```php
// email_verified_at is deliberately not fillable — a user must never be able
// to mark their own address verified through a profile form.
$user->email_verified_at = null;
$user->save();
```

Not `forceFill([...])->save()`. `forceFill` takes an array and so *looks* like mass
assignment while being the one form that has no guard at all — the reader has to know
the method to see the difference. Direct assignment names each column it writes, on its
own line, and the fact that it is deliberately stepping outside `#[Fillable]` is then
visible in the shape of the code rather than in the choice of method.

Before assigning directly, **check whether the column actually is fillable** — if it
is, this is an ordinary `update()` and none of the above applies.

Other genuine cases: writing `created_at`/`updated_at` explicitly (seeders, backfills),
and `saveQuietly()` where an observer must not fire. Both should carry a comment.

## A model never creates itself

A model describes the shape of a row. It does not know how one comes to exist.

```php
// ✗ on the model
class Order extends Model
{
    public static function createFromCart(Cart $cart, array $address): self { … }
    public function duplicate(): self { … }
}
```

```php
// ✓ in the domain service that owns the workflow
class CheckoutService
{
    public function handleCheckoutCompleted(CompletedCheckout $checkout): ?Order { … }
}
```

### Why

Creating a row is never only creating a row. It prices things, reserves stock, sends
mail, opens a transaction — so a `createFromCart()` on the model drags every one of
those dependencies into a class whose job was to describe a table. The model starts
resolving services, the service layer stops being the only place workflows live, and
the two grow separate versions of the same rules.

It also breaks the reading order. A model is the first file anyone opens to learn the
domain, and it should answer "what is an order" — not "how does checkout work",
which is a different question with a different owner (see `laravel-app-services`).

## A model doesn't orchestrate its own writes either

The same boundary applies to updates. A method on a model that persists a change —
especially one that touches other rows or enforces a rule while doing it — belongs in
a service.

```php
// ✗ on the model
class Address extends Model
{
    public function setAsDefault(): void
    {
        self::where('user_id', $this->user_id)
            ->where('id', '!=', $this->id)
            ->update(['is_default' => false]);

        $this->update(['is_default' => true]);
    }
}
```

```php
// ✓ in the service
class AddressService
{
    public function makeDefault(Address $address): void
    {
        DB::transaction(function () use ($address) {
            $address->user->addresses()
                ->whereKeyNot($address)
                ->update(['is_default' => false]);

            $address->update(['is_default' => true]);
        });
    }
}
```

The tell is the method name: `setAsDefault()`, `markAsShipped()`, `activate()`,
`transitionTo()` — a verb that describes a *workflow* rather than a fact about the row.

### Why this one bites

`setAsDefault()` is two writes that must both happen. On the model there is nothing to
put a transaction around, because the model has no idea whether it is being called
inside one — so the invariant it exists to maintain ("exactly one default") is the very
thing it cannot guarantee. Interrupted halfway, the user has zero default addresses.

It also hides its blast radius. `$address->setAsDefault()` reads like it writes one
row; it writes every address the user owns. A service method named `makeDefault(Address
$address)` sits at the layer where a transaction is normal and where touching sibling
rows is expected.

And rules attract more rules. Today it demotes siblings; tomorrow it validates the
country, logs activity, syncs to the payment provider. Each addition is a two-line diff
that passes review, and the model — the file everyone opens to learn what an address
*is* — becomes the file that knows how checkout works.

### The line

Ask what the method changes:

| Method does | Where it goes |
|---|---|
| Answers a question about this row (`isPaid()`, `refundableAmount()`) | Model |
| Reads a related row to answer it (`canTransitionTo()`) | Model |
| Writes one column, no rule, no siblings (`$model->update([...])` at the call site) | Caller |
| Writes with a rule, a transaction, or other rows | **Service** |

A model may still be *passed* to a service and updated there. What it must not do is
own the sequence.

### What is still fine on a model

- **Creating a *related* record through a relation.** `$order->addSystemNote($body)`
  creating an `OrderNote` is the model's own relationship, not a copy of itself.
- **Finders that return `self`.** `Coupon::findValid($code, $subtotal): ?self` reads
  a row; it doesn't create one.
- **Filling a column on the way in.** A `booted()` hook or observer that sets
  `order_number` before insert is completing a row, not constructing one.
- **Factories.** `database/factories` exists to build models; that is its whole job.

## The check

```sh
grep -rnE 'new (Order|Product|User|…)\(' app/     # model instantiation
grep -rn '\->save()' app/                          # then look at what precedes each
grep -rnE 'function [a-z]\w*\(.*\): *(self|static)' app/Models/   # self-returning methods
```

For each `save()`, look at the lines above it: if they are assignments building a new
record, it is this skill's bug. If they are `fill()` on a row that already exists, it
is an update and out of scope here.
