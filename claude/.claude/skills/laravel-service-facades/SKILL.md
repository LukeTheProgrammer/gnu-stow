---
name: laravel-service-facades
description: How app code reaches a service in app/Services — always through a facade in app/Facades, never by naming the service class or interface at the call site. Use when adding a service, adding a facade, or when a class from app/Services appears in a constructor, controller, job, model, or another service.
---

# Reaching services through facades

A service in `app/Services` is named in exactly two places: the binding in
`AppServiceProvider`, and the facade that fronts it. Everywhere else — controllers,
jobs, models, other services — calls the **facade**.

```
app/Services/<Domain>/<Domain>Interface.php   ← the contract
app/Services/<Domain>/<Vendor>/…              ← the implementation
app/Facades/<Domain>.php                      ← the only thing callers name
```

## The three pieces

**1. The facade** — accessor string, nothing else. No methods, no docblock methods
that drift from the interface.

```php
namespace App\Facades;

use Illuminate\Support\Facades\Facade;

class Payments extends Facade
{
    protected static function getFacadeAccessor()
    {
        return 'Payments';
    }
}
```

**2. The binding** — the accessor string maps to the interface in the `$bindings`
array on `AppServiceProvider`. The interface maps to a concrete implementation in
`register()`, where constructor arguments and config are resolved.

```php
class AppServiceProvider extends ServiceProvider
{
    public $bindings = [
        'Payments' => PaymentInterface::class,
    ];

    public function register(): void
    {
        $this->app->bind(PaymentInterface::class, fn ($app) => new StripePayment(
            $app->make(StripeClient::class),
            $app,
            config('services.stripe.webhook_secret'),
        ));
    }
}
```

Two hops on purpose: `$bindings` is the public name callers use, `register()` is
where the implementation is chosen. Swapping providers touches only the second.

**3. The call site** — imports the facade and calls it statically.

```php
use App\Facades\Payments;

$session = Payments::createCheckoutSession($request);
```

## Rules

- **Never type-hint a service class or its interface in a constructor.** If
  `PaymentInterface $payments` appears in a signature, it should be a `Payments::`
  call in the body instead. This holds for controllers, jobs, listeners, commands,
  other services — everything.
- **Never `new` a service, and never `app(SomeInterface::class)`.** Both name the
  class the facade exists to hide.
- The facade is named for the **domain**, not the implementation — `Payments`, not
  `StripePayments`.
- The facade accessor string matches the facade class name (`'Payments'`). Do not
  use the interface's FQCN as the accessor; the string is the stable public name.
- Everything else the service is (interface in the app's vocabulary, no vendor types
  crossing the implementation directory, DTOs beside the interface) still applies —
  see `laravel-third-party-services`. The facade fronts that structure; it does not
  replace it.
- Value objects and DTOs are still imported directly at call sites. Only the
  *service* goes behind the facade.

## Why

Constructor injection spreads a service's type across every class that uses it. Each
one is harmless alone, but the type ends up in dozens of signatures, and the call
sites and the wiring are interleaved — you cannot read a controller's constructor
without reading the container. The facade collapses that to one name, imported where
it is used and nowhere else, so what a class actually depends on is visible in its
body rather than assembled at the top.

It also keeps the swap cheap. With a facade, the entire coupling surface is the
accessor string and one binding line, and it does not matter how many callers there
are. `Payments::shouldReceive('refund')` still fakes it in a test.

## Adding a new service

1. Interface in `app/Services/<Domain>/`, implementation beneath it.
2. Facade in `app/Facades/<Domain>.php` returning `'<Domain>'`.
3. `'<Domain>' => <Domain>Interface::class` in `AppServiceProvider::$bindings`, plus
   the concrete binding in `register()`.
4. Call it as `<Domain>::method()`.

## The check

Grep for the interface name across `app/`. There should be exactly two hits: the
interface's own file and `AppServiceProvider`. A hit in a constructor signature is
the thing this skill exists to prevent — replace it with a facade call and delete the
import and the promoted property.
