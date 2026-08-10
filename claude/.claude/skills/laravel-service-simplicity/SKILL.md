---
name: laravel-service-simplicity
description: A service in app/Services stays an entry point — each operation it performs moves into its own verb-named invokable action in <Domain>/Actions/, non-operations go in <Domain>/Helpers/, and the service keeps a one-line delegating wrapper so the facade API never changes. Everything inside the domain calls back through the facade. Use when a service class grows a second job, when two of its methods share a private helper, or when adding an operation to a service that already has several.
---

# A service delegates; it does not accumulate

A service is the domain's entry point. It is not where the domain's work lives.

Every operation the domain performs — every method that writes something, coordinates
several models, or runs a multi-step process — is **one invokable action class**. The
service holds one line per operation and nothing else.

**Exactly one `.php` file sits at the root of a domain folder: the service.** Everything
else is in a subdirectory.

```
app/Services/Orders/
    OrderService.php          ← the only root file; one delegating line per operation
    Actions/
        UpdateOrder.php
        CancelOrder.php
        ApplyRefund.php
    Helpers/
        OrderVersion.php      ← machinery that is not an operation
```

## The shape

An action is `final`, named for what it does, and has one `__invoke`. It reaches the
rest of its own domain **through the facade**, so it needs no constructor at all:

```php
namespace App\Services\Orders\Actions;

use App\Facades\Orders;

final class CancelOrder
{
    public function __invoke(Order $order, ?string $reason, ?string $version): void
    {
        Orders::assertNotStale($order, $version);
        // …
        Orders::addNote($order, 'Refund failed during cancellation. ' . $message);
    }
}
```

The service constructs the action where it uses it and delegates. **No constructor, no
properties** — an action has no dependencies to wire and no state to carry between
calls, so injecting one buys nothing and only hides which method uses what:

```php
class OrderService
{
    public function cancel(Order $order, ?string $reason, ?string $version): void
    {
        (new CancelOrder)($order, $reason, $version);
    }

    public function assertNotStale(Order $order, ?string $version): void
    {
        (new OrderVersion)->assertNotStale($order, $version);
    }
}
```

Each method is then the whole of what it does, readable without scrolling to a
constructor. This is the one place `new` is correct — see the note under Rules.

**The facade API does not change when you split.** `Orders::cancel()` means the same
thing before and after, so extracting an action is invisible to every call site and can
be done without touching controllers, jobs, or tests. That is the whole reason the
wrapper exists — do not skip it and let callers reach an action directly.

## Everything goes through the facade

The service is the only thing that names an action or a helper class. Actions do not
construct each other and do not construct helpers — they call `Orders::` like any other
caller does.

```php
Orders::assertNotStale($order, $version);   // ✓ from inside UpdateOrder
(new OrderVersion)->assertNotStale(…);      // ✗ only the service may do this
$this->version->assertNotStale(…);          // ✗ injected collaborator
```

This is what keeps the domain's whole vocabulary in one file. `OrderService` lists
everything the domain can do; nothing reaches a piece of it by a private route that the
service does not also expose. It also means a helper can move, be renamed, or be
absorbed into another class without touching a single action.

There is no construction cycle: an action's dependency on the service is resolved when
`__invoke` runs, not when the action is built, and actions have no constructors. The
service itself is a **singleton** — see `laravel-service-facades` — so the entry point
is built once, and the actions behind it are empty objects created and discarded per
call.

## When to split

There is no line count. A 400-line service doing one thing coherently is fine; a
120-line one doing two is not. Split when any **one** of these is true:

- **Two or more public methods share a private helper** nothing else calls. The helper
  and its callers are one thing wearing the class's clothes.
- **A group of methods answers to a different caller** than the rest — a webhook
  controller versus an admin screen, a queue worker versus a request.
- **The class docblock needs the word "and"** to say what the class is for. If the
  honest summary is "the admin actions *and* the money-movement facts the provider
  reports", that "and" is the seam.

Any one signal is enough. Do not wait for all three, and do not argue a signal away
because the class "isn't that big yet" — size is the symptom, not the trigger.

## What is not an action

An action is an **operation**. Plenty of a service's surface is not:

- **Pure derivations** — a value computed from a model with no write. Move to the model
  as an accessor if they are really about one record; otherwise they are a helper.
- **Query lookups** used in several places are a **scope** on the model, not an action
  and not a private service helper. See `laravel-service-internal`. A scope states its
  condition and nothing else — guarding a nullable argument is the caller's job, so
  scope parameters are not nullable:

  ```php
  #[Scope]
  protected function forPaymentIntent(Builder $query, string $reference): Builder
  {
      return $query->where('stripe_payment_intent_id', $reference);
  }
  ```
- **A precondition belonging to one action** — "may this run yet, and if not why" — is
  a second public method on *that action*, not a class of its own:

  ```php
  final class ResendConfirmation
  {
      public function __invoke(Order $order): void { … }

      /** When this may next run, or null if it can run now. */
      public function availableAt(Order $order): ?Carbon { … }
  }
  ```

  The service delegates to it the same way: `(new ResendConfirmation)->availableAt($order)`.

- **Everything else** — shared guards, fingerprints, formatters, anything that is not an
  operation and does not belong on a model — is a **helper** in `<Domain>/Helpers/`.
  Noun-named for what it is: `OrderVersion`, not `OrderVersionService`, not
  `OrderHelper`, and never a trait. A helper may hold several related methods; it is a
  cohesive thing, not a bag. If a helper starts writing, it was an action all along.

## Rules

- **Verb + object, imperative**: `CancelOrder`, `ApplyRefund`, `OpenDispute`. Not
  `OrderCanceller`, not `CancelOrderHandler`, never `Manager`/`Service`/`Doer`.
- **One `__invoke`**, plus at most one precondition method as above. A second operation
  is a second class.
- **One root file per domain folder.** `<Domain>Service.php` and nothing else; actions
  in `Actions/`, helpers in `Helpers/`, DTOs and exceptions in their own folders as
  `laravel-service-internal` describes.
- **Actions have no constructor.** Anything they need from their own domain arrives via
  `<Domain>::`; anything from another domain via that domain's facade. If an action
  wants a constructor dependency, it is naming something the service should be exposing.
- **The service has no constructor either.** It writes `(new SomeAction)(…)` inside the
  method that needs it. This is the sole exception to the "never `new`" rule in
  `laravel-service-facades`: that rule protects *services*, which are swappable and
  sit behind a facade. An action is neither — it is an internal, stateless,
  dependency-free implementation detail of the one class allowed to name it, so the
  container adds a lookup and buys no seam. Everything else still goes through its
  facade.
- **Only the service names an action or helper class.** A class name from `Actions/` or
  `Helpers/` appearing anywhere else — another action, a controller, a job, **a test** —
  is this skill's bug. Tests are not an exception: they exercise the domain through
  `<Domain>::` like every other caller, and fake it with `<Domain>::shouldReceive()`.
  A test that reaches past the facade to an action is asserting on an implementation
  detail, and it is the reason a refactor that changed nothing observable still turns
  the suite red.
- **Private helpers move with their caller.** A helper used by exactly one extracted
  action becomes a private method on that action, and stops being visible to anything
  else. This is most of the size reduction.
- **The service keeps no state at all** — no constructor, no properties, no consts that
  belong to one operation. A constant used by a single action lives on that action.

## Why

A service accumulates because every new operation has an obvious home in it, and no
single addition looks like a problem. The result is a class that several unrelated
features all have to open, where a helper written for one operation is silently within
reach of the next, and where nothing tells you which private methods belong to which
public one.

Splitting on operations makes those boundaries physical. A change to how refunds work
opens one file that contains the refund logic and nothing else, and two features stop
sharing a merge surface.

What the split deliberately does *not* buy is a finer-grained testing seam. The domain
is tested through its facade, as one thing, whatever it happens to be made of inside —
so the whole of `Actions/` and `Helpers/` stays free to be reorganised without a single
test changing. That is the point: the file layout is an internal decision, and internal
decisions should not be load-bearing for anyone outside the folder.

Routing every internal call back through the facade is what stops the split from just
relocating the tangle. Without it, actions accumulate references to each other and the
domain becomes a graph nobody can see the shape of — the same coupling as the 500-line
class, now spread across a directory and harder to read. With it, `OrderService`
remains a complete and honest index of what the domain does, and every arrow inside the
folder points at that one file.

## Worked example

`Orders\OrderService` at 514 lines, whose own docblock says it holds "the admin
actions … **and** the money-movement facts the payment provider reports back":

| Was | Becomes |
|---|---|
| `update`, `cancel` | `Actions\UpdateOrder`, `Actions\CancelOrder` |
| `addNote` + private `systemNote` | one `Actions\AddNote` with a nullable author; the payment actions call `Orders::addNote()` |
| `applyRefund`, `applyPaymentFailure`, `openDispute`, `closeDispute` | one action each; they answer to the webhook controller, not the admin UI |
| `resendConfirmation` + `resendAvailableAt` | `Actions\ResendConfirmation` with `availableAt()` as its precondition method |
| `assertNotStale`, `versionOf` | `Helpers\OrderVersion` — no write, so not an action |
| `diff`, `recordRefundFailure` | private methods on `UpdateOrder` and `CancelOrder` |
| `findOrderByPayment` | a scope on `Order`, with the null-reference guard back in the callers |
| `recipientFor` | an accessor on `Order` — it was about one record all along |
| `generateOrderNumber` | stays on the service — a pure derivation, no write, nothing shares it |

514 lines become a 119-line service of thirteen one-line methods and nothing else,
eight actions of 25–115 lines, and one helper. `Orders::` still means everything it
meant before.

## Adding one

1. `app/Services/<Domain>/Actions/<VerbObject>.php`, `final`, one `__invoke`, no
   constructor.
2. Move the method body in; move its private helpers with it.
3. Anything it needs from its own domain becomes a `<Domain>::` call — add a delegating
   method on the service if one is missing.
4. Leave a one-line delegating method on the service with the identical signature.
5. Call sites do not change. If one had to, the wrapper is wrong.

## The check

Three greps:

- Open any `<Domain>Service.php`. Every public method should be a single line that
  delegates. A body with branching, a transaction, or more than one statement is an
  operation that has not been extracted yet.
- `ls app/Services/<Domain>/*.php` should print exactly one file.
- Grep the domain folder for `use App\Services\<Domain>\` outside the service, and for
  `__construct` anywhere in it. Both should be empty — no class in the folder has
  constructor dependencies, so nothing needs wiring.
