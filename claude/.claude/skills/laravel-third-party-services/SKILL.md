---
name: laravel-third-party-services
description: How to structure Laravel integrations with third-party services (payment providers, email/SMS senders, storage, search, shipping, CRMs, any external HTTP API). Use when adding a new external service, when touching code that imports a vendor SDK, or when a vendor class name appears in a controller, job, model, or another service.
---

# Third-party services in Laravel

Every third-party integration gets **an interface the app depends on** and **a
vendor-specific implementation the app never names**.

```
app/Services/<Domain>/<Domain>ServiceInterface.php   ← what the app talks to
app/Services/<Domain>/<Vendor>/<Vendor>Service.php   ← the only file that knows the vendor
```

For example, an app sending email through Mailjet:

```
app/Services/Mail/MailServiceInterface.php
app/Services/Mail/Mailjet/MailjetService.php
```

Bind the interface to the implementation in a service provider, and type-hint the
**interface** everywhere else.

```php
// AppServiceProvider::register()
$this->app->bind(MailServiceInterface::class, MailjetService::class);
```

```php
// A caller — no vendor name anywhere
public function __construct(private readonly MailServiceInterface $mail) {}
```

## Why

Swapping vendors, or standing one up in a test, should be a one-line binding change.
That only holds if the vendor's types never escape its own directory. The failure
mode is quiet, and it always runs the same way.

The integration starts out fine — one class, one vendor SDK import. Then a controller
needs the session object the vendor just returned, and type-hinting the vendor's class
is the shortest path, so it happens *just this once*. Then a job needs the same thing.
Then a model accessor reaches for a vendor constant. Nothing breaks at any step; each
one is a two-line diff that passes review. But the vendor is now load-bearing across
controllers, jobs, and services, and it can't be replaced — or faked in a test —
without touching all of them.

That is the outcome this pattern exists to prevent.

## Naming

**The vendor's name appears only inside the implementation directory.** Not just in
types — in class names, method names, variables, comments, and user-facing strings
too. A `MailjetService` is correct; a `sendViaMailjet()` called from a controller is
not, and neither is `$stripeProductId` in a service that no longer imports Stripe.

The test: grep the vendor's name across `app/`. Every hit outside
`app/Services/<Domain>/<Vendor>/` is a leak, even when it compiles fine.

| Instead of | Use |
|---|---|
| `createStripeCheckoutSession()` | `createCheckoutSession()` |
| `$stripeProductId` | `$remoteProductId` |
| `$product->syncedToStripe()` | `$product->syncedToProvider()` |
| `App\Services\Stripe\SyncResult` (own class) | `App\Services\Catalog\SyncResult` |
| `'Product is not synced to Stripe.'` | `'…not synced to the payment provider.'` |

A vendor-named class that no longer references the vendor is the easiest version of
this to miss — the name keeps advertising a coupling that the code has already shed,
and the next person re-creates it because the name told them it was fine.

Two things legitimately keep the vendor's name, because changing them has a cost
beyond the codebase:

- **Database columns** (`stripe_product_id`, `stripe_payment_intent_id`) — a rename
  is a migration over live data. Acceptable to leave; the model accessor around them
  should be neutral.
- **Config keys and externally-published routes** (`services.stripe.*`, a webhook URL
  already registered in the provider's dashboard) — these *are* vendor-specific, or
  are known by an outside system.

## Rules

- The interface is defined in the app's own vocabulary — `send()`, `charge()`,
  `refund()` — not the vendor's. If a method name or parameter only makes sense
  because of the vendor's API, the abstraction has leaked.
- **No vendor type crosses the implementation directory's boundary.** Not in a
  signature, not in a return type, not in a thrown exception. Vendor exceptions get
  caught and rethrown as the app's own; vendor response objects get mapped to the
  app's own DTOs — a readonly class of plain typed values, living beside the
  *interface* rather than the implementation:

  ```php
  final readonly class SyncResult
  {
      public function __construct(
          public string $remoteId,
          public bool $created,
      ) {}
  }
  ```
- Credentials are read from `config()` in the implementation's constructor or in the
  provider binding — never `env()` outside `config/`.
- One interface per *capability*, not per vendor. If a vendor covers two capabilities
  (payments and subscriptions), that's two interfaces, possibly one class
  implementing both.
- Don't add an interface speculatively for something that isn't a third-party
  service. Internal domain services (`CartService`, `CouponService`) have no second
  implementation coming and don't need one — they still get a domain folder and a
  facade, just no interface. See `laravel-app-services`.

## Inbound: webhooks and callbacks

The same rule applies in reverse when the vendor calls *you*. The interface takes the
request body **as an opaque string** and the implementation owns everything about it:

```php
public function handleWebhook(string $payload, string $signature): void;
```

The controller verifies nothing, parses nothing, and dispatches nothing — it hands
over the raw body and maps exceptions to status codes. Which events exist, what they
are called, how they are encoded, and which header carries the signature are all
provider vocabulary. Expose a `signatureHeader(): string` on the interface rather than
naming the vendor's header at the call site.

Do **not** define a neutral `WebhookEvent { type, payload }` DTO and hand it out. It
looks provider-agnostic, but `type` is the vendor's event name and `payload` is the
vendor's array — every caller that switches on them is coupled to the vendor while
appearing not to be. That is worse than an honest coupling, because the next provider
silently has to emit fake Stripe event names to keep the callers working.

The implementation translates each event into **plain typed values** and calls
provider-neutral app services:

```php
// inside the Stripe implementation
'charge.refunded' => $this->orders()->applyRefund(
    $object['payment_intent'] ?? null,
    ($object['amount_refunded'] ?? 0) / 100,
    (bool) ($object['refunded'] ?? false),
),
```

The order-domain service takes `(?string $paymentReference, float $amount, bool
$full)` — no payload, no vendor keys — so the business rules stay shared across
providers while payload interpretation stays per-provider. Unrecognized events are
acknowledged and ignored, never an error.

Externally-registered webhook **URLs** keep their vendor name (see Naming); the
controller and services behind them do not.

## Exception: framework extension points

When Laravel or Symfony **already defines a contract for the capability**, implement
that contract instead of inventing a parallel one alongside it. The framework's
interface is already the seam, and the driver is already swappable by config.

The clearest case is mail. `MailjetTransport extends AbstractTransport`, registered
via `Mail::extend('mailjet', ...)`, is a Symfony Mailer driver — callers use
`Mail::to(...)` and never name Mailjet, so switching providers is already a
`MAIL_MAILER` env change. Wrapping that in a second `MailServiceInterface` adds a
layer without adding a seam. The same reasoning covers filesystem drivers, cache
stores, queue connections, and broadcast drivers.

Apply this pattern when the app is calling a vendor API **directly** — a payments
SDK, a shipping rates API, a CRM — where no framework contract exists.

If unsure which case applies, ask: *does the app already reach this service through a
framework facade or contract?* If yes, it's an extension point — write a driver. If
the app imports the vendor SDK itself, it's an integration — write an interface.
