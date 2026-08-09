---
name: laravel-model-attributes
description: Laravel 13 replaces most Eloquent model configuration properties and naming conventions with PHP attributes — #[Fillable], #[Scope], #[ObservedBy], #[Table] and the rest. Use when adding or editing a model, adding a scope, or when a `protected $property` or a `scopeFoo()` method appears on a model.
---

# Model attributes

Laravel 13 expresses model configuration as **PHP attributes** rather than protected
properties and magic method names. Use the attribute in every case where one exists.

```php
// ✗ pre-13
class ActivityLog extends Model
{
    protected $fillable = ['subject_type', 'subject_id', 'action'];

    public function scopeNewestFirst(Builder $query): Builder
    {
        return $query->orderByDesc('created_at');
    }
}
```

```php
// ✓
#[Fillable(['subject_type', 'subject_id', 'action'])]
class ActivityLog extends Model
{
    #[Scope]
    protected function newestFirst(Builder $query): Builder
    {
        return $query->orderByDesc('created_at');
    }
}
```

Both call sites are unchanged — `ActivityLog::newestFirst()` still works, and mass
assignment behaves identically. This is about where the configuration is *stated*.

## The mapping

All of these live in `Illuminate\Database\Eloquent\Attributes`.

| Was | Now |
|---|---|
| `protected $fillable` | `#[Fillable([...])]` |
| `protected $guarded` | `#[Guarded([...])]`, or `#[Unguarded]` for `$guarded = []` |
| `protected $hidden` | `#[Hidden([...])]` |
| `protected $visible` | `#[Visible([...])]` |
| `protected $appends` | `#[Appends([...])]` |
| `protected $touches` | `#[Touches([...])]` |
| `protected $connection` | `#[Connection('name')]` |
| `protected $dateFormat` | `#[DateFormat('U')]` |
| `protected $table` / `$primaryKey` / `$keyType` | `#[Table(name: …, key: …, keyType: …)]` |
| `public $incrementing = false` | `#[WithoutIncrementing]` |
| `public $timestamps = false` | `#[WithoutTimestamps]` |
| `public function scopeFoo(Builder $q)` | `#[Scope]` on `foo(Builder $q)` |
| `static::addGlobalScope(...)` in `booted()` | `#[ScopedBy([...])]` |
| observer registered in a provider | `#[ObservedBy([...])]` |
| `newCollection()` | `#[CollectedBy(CustomCollection::class)]` |
| `newEloquentBuilder()` | `#[UseEloquentBuilder(CustomBuilder::class)]` |
| `boot{TraitName}()` in a trait | `#[Boot]` on any static method |
| `initialize{TraitName}()` in a trait | `#[Initialize]` on any method |

`#[Table]` also takes `incrementing:`, `timestamps:` and `dateFormat:`, so a model that
overrides several of those states them once instead of as four properties.

### Local scopes

The `scope` prefix is what the attribute replaces — with `#[Scope]`, the method is
named for what it does and nothing parses its name:

```php
#[Scope]
protected function newestFirst(Builder $query): Builder
{
    return $query->orderByDesc('created_at')->orderByDesc('id');
}
```

The method must not be `private` (the framework rejects it); `protected` is the
default choice, since it is only ever reached through the query builder.

## Synthetic attributes return `Attribute`

An accessor or mutator is a method named for the attribute that returns an
`Illuminate\Database\Eloquent\Casts\Attribute`. The `getFooAttribute()` /
`setFooAttribute()` name-prefix convention is the old form and is not used.

```php
// ✗
public function getUnitPriceAttribute(): float
{
    return $this->pack_id ? (float) $this->pack->price : $this->variant->effectivePrice();
}
```

```php
// ✓
protected function unitPrice(): Attribute
{
    return Attribute::get(
        fn () => $this->pack_id ? (float) $this->pack->price : $this->variant->effectivePrice(),
    );
}
```

The method is named in `camelCase` for the attribute (`unitPrice` → `$item->unit_price`),
is `protected`, and returns `Attribute` — never the value's own type. Read-only
attributes use `Attribute::get(...)`; a pair uses `Attribute::make(get: …, set: …)`,
where the setter returns either a value for its own column or an array of columns to
write:

```php
protected function fullName(): Attribute
{
    return Attribute::make(
        get: fn () => trim("{$this->first_name} {$this->last_name}"),
        set: fn (string $value) => [
            'first_name' => Str::before($value, ' '),
            'last_name' => Str::after($value, ' '),
        ],
    );
}
```

Add `->shouldCache()` when the computation is expensive and the underlying columns
cannot change mid-request. Do not cache one that reads a relation you may modify.

Two things this buys beyond consistency. The getter and setter for one attribute sit in
one method instead of two methods filed apart alphabetically, and the name is free of
the `get…Attribute` sandwich, so `unitPrice()` is greppable as the thing it computes.

**A method whose result is not an attribute stays an ordinary method.** If callers say
`$model->thing()` rather than `$model->thing`, it is a helper, and giving it an
`Attribute` return type only to call it as a property is a worse fit than leaving it
alone.

## What is *not* an attribute

Do not invent attributes that do not exist. These stay as they are:

- **Casts** — `protected function casts(): array`, the method form. There is no
  `#[Casts]`. (See `laravel-model-enums` for what belongs in it.)
- **`$with`, `$perPage`** — still properties; no attribute ships for them.
- **Relations** — ordinary methods returning a relation instance.
- **Accessors and mutators** — methods returning
  `Illuminate\Database\Eloquent\Casts\Attribute`, per the section above. That
  `Attribute` is a *cast object*, not a PHP attribute; the two are unrelated despite
  the name, and `#[Attribute]` on a model method is always a mistake.
- **`booted()`** — stays a method. `#[Boot]` is for *traits*: it frees a trait's boot
  method from having to be named `bootMyTrait()`. It is not a replacement for a
  model's own `booted()`, and the two run at different points.

If the configuration you are moving is not in the table above, check
`vendor/laravel/framework/src/Illuminate/Database/Eloquent/Attributes/` before
assuming an attribute exists.

## Don't over-apply

An attribute that only restates a convention is noise. Skip it when Laravel already
resolves the thing by name:

```php
#[Table('products')]          // ✗ Product already resolves to `products`
#[UsePolicy(ProductPolicy::class)]   // ✗ App\Policies\ProductPolicy is the convention
#[UseFactory(ProductFactory::class)] // ✗ same
```

`#[UsePolicy]`, `#[UseFactory]`, `#[UseResource]` and `#[UseResourceCollection]` earn
their place only when the class sits **off** the conventional path — a policy in a
different namespace, a factory shared between two models. Then the attribute is the
documentation for why the convention doesn't apply.

## Why

Model configuration is metadata about the class, not state belonging to instances, and
attributes put it where metadata belongs: above the declaration, visible before the
body, greppable as `#[Fillable` across every model at once. A protected property is a
runtime value that happens to be read at boot — which is why `$fillable` and
`$casts()` and `scopeFoo()` each had a different shape for the same job.

The naming conventions are the bigger win. `scopeFoo` and `bootMyTrait` encode intent
in a *string prefix*, so the method name has to carry two meanings at once, a rename
silently disables the behavior, and nothing but the framework's own reflection knows
the method is special. `#[Scope]` says it out loud, and the name is free to describe
only what the scope does.
