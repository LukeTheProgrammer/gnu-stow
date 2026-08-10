---
name: laravel-model-methods
description: What may live on an Eloquent model at all — five kinds of member, with every other method pushed to the enum, policy, service, or caller that owns the rule — and the order those members appear in. Use when adding any method to a model, when a model grows past its relationships, or when reviewing a model in app/Models.
---

# What belongs on a model, and in what order

Two rules, applied in this order:

1. **Does this member belong on the model at all?** Most don't.
2. **Only then:** what shape does it take, and where does it sit in the file?

Rule 2 is the easy one and most of this document, but rule 1 is the one that keeps
models small. Applying rule 2 alone just renames the bloat.

## Rule 1: a model holds five kinds of member

1. **Configuration** — casts and the framework hooks Laravel calls.
2. **Relationships.**
3. **Scopes.**
4. **Attributes** — values derived from this row's own loaded columns.
5. **Package hooks** — Scout, Media Library, and friends.

That is the list. **Any other method must justify its existence**, and the burden of
proof is on the method. This inverts the usual default, where a method is waved through
because it is short and reads nicely — which is exactly how a model ends up with thirty
of them.

### Every other method must name the home that rejected it

Models bloat because the model is the *nearest* place to put something, not the right
one. Before a plain method may stay, it has to fail all of these:

| If the method… | it belongs to |
|---|---|
| answers "which values of this enum allow X" | the **enum** (see `laravel-model-enums`) |
| answers "may this actor do X" | a **policy** (see `laravel-authorization-architecture`) |
| touches another model, orchestrates, or calls a vendor SDK | a **service** (see `laravel-service-internal`) |
| shapes a query | a **scope** |
| derives a value from this row's loaded columns, for more than one caller | an **attribute** |
| returns a new instance of this model | a **query helper** (see `laravel-model-creation`) |
| is none of the above | the **caller** — inline it |

The enum, the policy, and the service are where model methods go to *live*, not to die.
Most model bloat is lifecycle rules that had nowhere better to sit when they were
written — often because the status column was a bare string at the time.

### One caller is not a convention

The test that removes most of them: **a name used once is a local variable, not a model
member.**

```php
// ✗ on the model, called from exactly one place
public function isPaid(): bool
{
    return $this->stripe_payment_intent_id !== null;
}

// ✓ at the call site
$isPaid = $order->stripe_payment_intent_id !== null;
```

A member earns its place only when re-deriving the expression in several places could
let those places **drift apart**. That is the real risk a shared name protects against.
For a single-column check with one caller there is no drift to prevent, and the method
is pure ceremony — an extra name, an extra indirection, and one more thing to read past
when scanning the model.

**Do not over-correct into duplication.** Three call sites each inlining
`$order->status === OrderStatus::PENDING` is how rules drift, and is worse than the
method was. When more than one caller needs the same judgement, it keeps a home — the
question the table answers is *which* home, and the model is rarely it.

### Attributes are a shape, not an exemption

Converting a method to an Attribute does not shrink a model; it renames a member. Ask
rule 1 first. Only once a value has earned its place *and* is a zero-argument derivation
of this row's loaded state does it become an Attribute rather than a method.

Three things disqualify a member from being an Attribute outright, and they are worth
knowing because they are also hints that it may not belong on the model at all:

- **It takes an argument.** Attributes are zero-argument by construction.
- **It writes.** An attribute derives; it does not persist.
- **It is static.** A value manufactured for a record that does not exist yet is not a
  fact about a record.

## Rule 2: the order

1. **Properties** — traits, then constants, then `protected`/`public` properties.
2. **Eloquent framework methods** — the ones Laravel itself calls, not you.
3. **Relationships** — alphabetical, every one with a type-hinted return.
4. **The model's own methods** — scopes first (they finish the query-building half of
   the file), then accessors/mutators, then domain methods.
5. **Third-party package hooks** — Scout, Media Library, and friends, at the bottom.

No exceptions for "it's a small model" or "these two belong together". The point of a
fixed order is that it holds without being reasoned about.

## 1. Properties at the top

Every property sits above every method. Nothing is declared partway down the class.

```php
class Product extends Model implements HasMedia
{
    use HasFactory;
    use HasSlug;
    use SoftDeletes;

    public const RESERVATION_MINUTES = 15;

    protected $with = ['defaultVariant'];

    // …methods follow
}
```

Traits first (alphabetical, one `use` per line — not a comma-separated list, so a diff
adding one is a single line). Then constants, then properties.

Note that most configuration properties are attributes in Laravel 13 (`#[Fillable]`,
`#[Table]`) and live above the class declaration entirely — see
`laravel-model-attributes`. A model following that skill will often have no
configuration properties left, which is fine; the rule is about where they go *if* they
exist.

## 2. Eloquent framework methods next

Immediately below the properties, the methods Laravel itself calls:

```php
protected function casts(): array
protected static function booted(): void
protected static function newFactory(): Factory
public function getRouteKeyName(): string
public function uniqueIds(): array
```

`casts()` goes first when present — it is the closest thing the class has to a schema,
and it is what someone reads to find out what type a column arrives as.

This block is **Laravel's own hooks only**. A method that exists because a third-party
package is installed does not belong here no matter how framework-shaped it looks —
those go in block 5.

## 3. Relationships, alphabetical, type-hinted

Every relationship method carries a return type from
`Illuminate\Database\Eloquent\Relations` — `BelongsTo`, `BelongsToMany`, `HasMany`,
`HasOne`, `MorphMany`, `MorphTo`, and so on. Never bare, never `mixed`.

```php
public function category(): BelongsTo
{
    return $this->belongsTo(Category::class);
}

/**
 * Every product has at least one variant. A product without selectable
 * options has exactly one, whose option_values is empty.
 */
public function defaultVariant(): HasOne
{
    return $this->hasOne(ProductVariant::class)->oldest('id');
}

public function images(): HasMany
{
    return $this->hasMany(ProductImage::class);
}

public function variants(): HasMany
{
    return $this->hasMany(ProductVariant::class);
}
```

Sorted **alphabetically by method name** — not by relationship type, not by importance,
not by the order the tables were built. Any other ordering is a judgement call that the
next person will make differently, and the list stops being scannable. Alphabetical
also makes "does this model have an `orders()` relation?" a lookup rather than a read.

A relationship that needs explaining gets a docblock (as `defaultVariant()` above); the
docblock does not change its sort position.

Generic return types (`HasMany<ProductVariant, $this>`) are welcome where static
analysis is in play, but the concrete class name is the requirement.

## 4. The model's own methods below

Scopes, accessors, and domain methods live under the relationships, and are not
interleaved with them.

```php
#[Scope]
protected function published(Builder $query): Builder
{
    return $query->where('status', ProductStatus::PUBLISHED);
}

protected function displayName(): Attribute
{
    return Attribute::get(fn () => "{$this->name} ({$this->sku})");
}

public function effectiveTaxCode(): string
{
    return $this->stripe_tax_code ?: config('services.stripe.default_tax_code');
}
```

Within this block the groups come in a fixed order — **scopes, then accessors and
mutators, then domain methods** — and each group is alphabetical internally.

### Scopes are always fully typed

A local scope **always** type-hints its `$query` parameter and returns the same builder
class it was handed. No bare `$query`, no missing return type, no `void`:

```php
#[Scope]
protected function active(Builder $query): Builder      // ✓
protected function active($query)                       // ✗ untyped both ends
protected function active(Builder $query): void         // ✗ chain stops here
```

The builder class must **match on both ends**. Almost always that is
`Illuminate\Database\Eloquent\Builder`; a scope written against the query builder takes
and returns `Illuminate\Database\Query\Builder` instead. Mixing the two is the bug this
rule exists to surface — `Eloquent\Builder` in, `Query\Builder` out silently drops model
hydration and global scopes for everything downstream.

Returning the builder rather than mutating in place keeps scopes chainable
(`Product::active()->withPricing()`), which is how they are called in practice, and the
declared return type is what tells the reader — and static analysis, and the IDE — that
the chain continues. A `void` scope still works at runtime under `#[Scope]`, but it
cannot be composed and nothing warns you until the chain breaks.

Scopes taking extra arguments type-hint those too, and they follow `$query`:

```php
#[Scope]
protected function forSlug(Builder $query, string $slug): Builder
{
    return $query->where('slug', $slug);
}
```

### Placement

**Scopes go first, directly under the relationships.** Both are query-building: a
relationship says what this record can be joined to, a scope says how a set of them is
narrowed, and reading them back to back is how you learn what queries this model
supports. Everything below that line is about a single loaded instance — what an
attribute derives to, what a record can tell you about itself — which is a different
question, asked at a different time.

Accessors sit between the two because they straddle it: they are per-instance like the
domain methods, but like `casts()` they describe what a column *is* rather than what the
model *does*, so they read as the tail of the schema half of the file.

Alphabetical-within-group is a weaker rule than in the relationship block, since these
methods genuinely vary in kind, but apply it wherever the names don't argue for
something else.

Two things that belong further away than this file:

- A method that **creates an instance of the model** does not belong on the model at
  all — see `laravel-model-creation`.
- A method that reaches into other models or a third-party SDK is a service, not a
  model method — see `laravel-service-internal`.

## 5. Third-party package hooks last

Methods that exist only because a package is installed go at the very bottom, after
everything the model itself does:

```php
public function toSearchableArray(): array        // laravel/scout
public function shouldBeSearchable(): bool        // laravel/scout
public function searchableAs(): string            // laravel/scout

public function registerMediaCollections(): void  // spatie/laravel-medialibrary
public function registerMediaConversions(?Media $media = null): void

public function getActivitylogOptions(): LogOptions   // spatie/laravel-activitylog
public function tapActivity(Activity $activity): void
```

Group them **by package**, packages alphabetical by composer name, and within a package
put the methods in whatever order that package's own docs present them — the calling
sequence usually reads better than alphabetical (`registerMediaCollections()` before
`registerMediaConversions()`; `toSearchableArray()` before `shouldBeSearchable()`).

### Why the bottom rather than beside Laravel's hooks

They look like framework hooks, so the temptation is to file them with `casts()`. Three
reasons not to:

- **They are configuration for something outside the model.** `toSearchableArray()`
  describes a Meilisearch document; `registerMediaConversions()` describes image
  processing. Neither tells you anything about the record itself, which is what the top
  of the file is for.
- **They churn on a different clock.** These change when a package is upgraded or a
  search index is retuned — not when the domain changes. Keeping them in one block at
  the bottom means a package upgrade produces a diff that never touches the model's
  actual behavior.
- **They leave with the package.** Dropping Scout should be a deletion of one
  contiguous block plus a trait, not a hunt through the file.

The test is ownership: if the method's signature is defined by a `vendor/` interface or
base class that is **not** `Illuminate\*`, it goes here. `casts()` and `booted()` are
Laravel; `toSearchableArray()` is Scout.

## Worked example: applying rule 1

An `Order` carrying seven plain methods, and where each one goes:

| Method | Verdict |
|---|---|
| `isEditable()`, `isCancellable()`, `isAddressEditable()` | **enum** — each is "which statuses permit this", so it belongs on `OrderStatus` as `allowsEditing()` etc. |
| `canTransitionTo(OrderStatus $s)` | **delete** — a pass-through to `$order->status->canTransitionTo($s)`; takes an argument, adds nothing |
| `generateOrderNumber()` | **service** — static, and it manufactures a value for a record that does not exist yet |
| `addSystemNote(string $body)` | **caller** — it writes, and `$order->notes()->create([...])` says the same thing |
| `isPaid()` | **inline**, or an attribute if the name is worth keeping |
| `refundableAmount()` | **attribute** — real arithmetic over two of its own columns, several callers |

Seven methods become zero methods and one or two attributes, and every rule lands
somewhere it can be reused and tested on its own.

The lifecycle predicates are the important ones. Once they sit on the enum, a new status
forces every one of them to be considered — `match` is exhaustive — whereas on the model
they were a scattered set of `in_array` checks that a new case slips silently past.

**Watch the boundary as rules grow.** The enum route works only while the rule depends
*solely* on the enum value. The moment `isAddressEditable` also has to check
`tracking_number`, it stops being the enum's business: it is then a fact about the row
(attribute) or a decision about an actor (policy). Move it out rather than passing the
extra column into the enum.

## Reordering an existing model

Moving methods is a pure reshuffle: **no signature, body, or visibility changes in the
same pass**. Reorder first, verify the diff is move-only, then make behavioral changes
in a separate commit. A reordering diff that also edits a body is unreviewable, and the
one real risk here — a `protected static function booted()` that quietly depended on
declaration order, which it never does — is not worth confusing with actual edits.

Run rule 1 over the file **before** reordering — there is no point sorting members that
should not exist. Redistributing a method changes call sites, so do that as its own
commit, then reorder what survives as a pure move-only diff.

Check while you are in there:

- Plain methods that never justified themselves — apply the table above.
- Relationships with no return type — add the concrete `Relations\*` class.
- Scopes with a bare `$query` or no return type — type-hint both to the same `Builder`,
  and add the `return` if the body was mutating in place.
- Properties stranded below methods — hoist them, or convert to a Laravel 13 attribute.
- `casts` declared as a `protected $casts` array property — convert to the
  `protected function casts(): array` method, which then leads the framework block.
- Package hooks sitting in the Laravel block or interleaved with domain methods — sink
  them to the bottom and group them by package.
