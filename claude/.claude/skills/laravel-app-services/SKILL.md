---
name: laravel-app-services
description: How to structure the app's own domain services in app/Services — the ones with no third-party vendor behind them (cart, coupons, stock, checkout). Covers the domain folder, the one-word domain name, the facade, and when something should be a service at all. Use when adding a service class, when a `*Service.php` sits loose at the top of app/Services, or when naming a new domain.
---

# The app's own services

A service with no vendor behind it — cart, coupons, stock, checkout — gets the same
two things as a third-party integration: **a domain folder** and **a facade**. What it
does *not* get is an interface.

```
app/Services/<Domain>/<Domain>Service.php   ← the service; nothing else names it
app/Facades/<Domain>.php                    ← what callers name
```

```
app/Services/Cart/CartService.php    →  App\Facades\Cart
app/Services/Coupons/CouponService.php  →  App\Facades\Coupons
```

A loose `app/Services/CartService.php` at the top level is the thing this skill
corrects.

## No interface

`laravel-third-party-services` exists because a vendor can be swapped, and the
interface is the seam that makes swapping a one-line change. An internal service has
no second implementation coming. `CartServiceInterface` with exactly one implementer
is a file that must be edited twice for every method added, in exchange for nothing.

So the binding is one hop, straight to the concrete class:

```php
public $bindings = [
    'Payments' => PaymentInterface::class,   // third-party: via its interface
    'Cart' => CartService::class,            // app service: direct
];
```

The facade still fully hides the class, which is the part that mattered. If a genuine
second implementation ever appears, introducing the interface is a one-line change to
this array — every call site already says `Cart::`.

## Naming

**The domain is one word.** It names the folder, the facade, and the accessor string.
The class keeps its `Service` suffix — callers never write it, and it keeps the
service distinct from the model of the same name.

| Instead of | Domain | Class | Facade |
|---|---|---|---|
| `CartService.php` | `Cart` | `Cart\CartService` | `Cart::` |
| `CouponService.php` | `Coupons` | `Coupons\CouponService` | `Coupons::` |
| `StockReservationService.php` | `Stock` | `Stock\StockService` | `Stock::` |
| `VariantMatrixService.php` | `Variants` | `Variants\VariantService` | `Variants::` |
| `OrderActionService.php` | `Orders` | `Orders\OrderService` | `Orders::` |

Two-word names are a signal, not a style problem. `StockReservationService` and
`VariantMatrixService` are named after their *mechanism* — a reservation row, a matrix
— rather than the domain they serve. Once the mechanism is in the name, a second
service that touches the same domain by a different mechanism looks like it needs its
own class, and the domain ends up split across three files that all have to agree.
Naming the domain instead gives that logic exactly one home.

Keep a second word only when it names a genuinely separate domain that shares a prefix
by coincidence. If two candidates differ only by mechanism, they are one service.

Singular or plural: say the call out loud. `Cart::add()` and `Checkout::start()` are
one thing being acted on; `Coupons::apply()` and `Orders::cancel()` reach into a
collection. Match whichever reads as English.

Do **not** put the app's name, a layer name, or `Manager`/`Handler`/`Helper` in it.
`Helper` in particular means the contents have no domain — that is a sign the logic
belongs on a model or in the one caller that needs it.

## What belongs in a service

A service holds logic that **spans more than one model, or that a model shouldn't own**
— multi-step writes, transaction boundaries, rules that consult several tables.

Not everything deserves one:

- Logic about a single record's own state is a **model method or accessor**.
  `$order->isRefundable()` does not need an `OrderService`.
- A query used in several places is a **scope** or a query builder, not a service.
- Something used by exactly one controller action, once, can stay in the controller
  until a second caller shows up.

The failure mode is a service per controller — `ProductPageService`, `CheckoutStepTwoService` —
which is the controller's structure copied one directory over. Services are named for
domains, and a domain outlives the screens that display it.

## Structure inside the folder

The folder exists so the domain has somewhere to grow. Put whatever the service owns
beside it, in the app's own vocabulary:

```
app/Services/Cart/
    CartService.php
    CartTotals.php        ← readonly DTO, if the service returns a value object
    Exceptions/
        CartLocked.php
```

Same rules as anywhere else: DTOs are `final readonly` classes of plain typed values,
exceptions are the app's own. Callers import DTOs and exceptions directly — only the
*service* goes behind the facade.

Sub-services within one domain are fine (`Cart\CartService`, `Cart\CartMergeService`)
when one is genuinely internal to the other. Only the entry point gets a facade; the
inner one is constructor-injected into it and never called from outside the folder.

## Adding one

1. `app/Services/<Domain>/<Domain>Service.php`.
2. `app/Facades/<Domain>.php` returning `'<Domain>'` — see `laravel-service-facades`
   for the facade and call-site mechanics.
3. `'<Domain>' => <Domain>Service::class` in `AppServiceProvider::$bindings`.
4. Call it as `<Domain>::method()`. Never `new`, never a constructor type-hint.

## The check

Nothing should sit directly in `app/Services/` — every `.php` there is either in a
domain folder or is a service without a facade. Both are this skill's bug.
