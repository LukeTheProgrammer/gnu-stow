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

**2. The binding** — the accessor string maps to the interface in the `$singletons`
array on `AppServiceProvider`. The interface maps to a concrete implementation in
`register()`, where constructor arguments and config are resolved.

```php
class AppServiceProvider extends ServiceProvider
{
    public $singletons = [
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

Two hops on purpose: `$singletons` is the public name callers use, `register()` is
where the implementation is chosen. Swapping providers touches only the second.

### `$singletons`, not `$bindings`

Both properties take the same `accessor => class` shape, so this is a one-word choice —
and it should be `$singletons` every time.

A service is **stateless**: it holds injected dependencies and nothing else. There is
no per-request state to keep apart, so a second instance is not isolation, it is just a
second instance. With `$bindings` the container rebuilds the service — and its entire
dependency graph — on every single facade call, which is pure waste and gets worse the
deeper the graph goes. A service that composes a dozen collaborators is rebuilt a dozen
objects deep each time someone calls it.

If a service ever does need per-call state, that is the bug. Pass the state as an
argument or return it; do not reach for `$bindings` to paper over it.

**3. The call site** — imports the facade and calls it statically.

```php
use App\Facades\Payments;

$session = Payments::createCheckoutSession($request);
```

## Rules

- **Never type-hint a service class or its interface in a constructor.** If
  `PaymentInterface $payments` appears in a signature, it should be a `Payments::`
  call in the body instead. This holds for controllers, jobs, listeners, commands —
  everywhere a service is *used*.
- **One exception: a service injecting a service it fronts.** Where one service is the
  public face of another and exists to delegate to it, that is a composition point, not
  a call site, and the collaborator is injected:

  ```php
  class ProductService
  {
      public function __construct(private ProductSyncServiceInterface $syncService) {}

      public function sync(Product $product): SyncResult
      {
          return $this->syncService->sync($product);
      }
  }
  ```

  The reasoning the main rule rests on does not apply here. That rule exists because
  injection spreads a service's type across dozens of unrelated signatures; this is one
  signature, in the single class whose job is to front that service. Reaching for the
  facade instead would resolve the container again in every method, for a dependency
  that cannot change while the service lives — and a fronting service should not need
  its own accessor string to reach the thing it wraps.

  It is an exception, not a loosening: the injected type must be a service the injecting
  service delegates to, the injecting service must be the only class naming it, and
  everything that merely *uses* a service still calls the facade. When a service is
  fronted this way it usually should not keep a facade of its own — two public routes to
  the same methods is one too many.
- **Never `new` a service, and never `app(SomeInterface::class)`.** Both name the
  class the facade exists to hide.
- **Services are registered in `$singletons`, never `$bindings`.** A service holding
  state that makes a shared instance unsafe is a service to fix, not to rebind.
- The facade is named for the **domain**, not the implementation — `Payments`, not
  `StripePayments`.
- The facade accessor string matches the facade class name (`'Payments'`). Do not
  use the interface's FQCN as the accessor; the string is the stable public name.
- Everything else the service is (interface in the app's vocabulary, no vendor types
  crossing the implementation directory, DTOs beside the interface) still applies —
  see `laravel-service-external`. The facade fronts that structure; it does not
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
3. `'<Domain>' => <Domain>Interface::class` in `AppServiceProvider::$singletons`, plus
   the concrete binding in `register()`.
4. Call it as `<Domain>::method()`.

## The check

Grep for the interface name across `app/`. There should be exactly two hits: the
interface's own file and `AppServiceProvider`. A hit in a constructor signature is
the thing this skill exists to prevent — replace it with a facade call and delete the
import and the promoted property.
