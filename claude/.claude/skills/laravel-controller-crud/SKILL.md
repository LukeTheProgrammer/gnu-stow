---
name: laravel-controller-crud
description: A resource controller gets one `update` method backed by one update form request whose fields are all optional — not a method per editable property (status(), tracking(), shippingAddress()). Use when adding a controller action that writes to an existing model, when a controller grows a verb-named method that sets one field, or when a route file collects several PUT/POST endpoints under the same resource.
---

# One `update`, not a method per field

A resource controller has seven actions at most: `index`, `create`, `store`, `show`,
`edit`, `update`, `destroy`. Everything that modifies an existing record goes through
`update` — one method, one form request, one route.

The anti-pattern this exists to stop looks like `Admin/OrderController`: `status()`,
`tracking()`, `shippingAddress()` — three methods, three form requests, three routes,
each setting one property of the same model. Each one duplicates the authorize call,
the concurrency token rule, and the redirect. Adding a fourth editable field means
touching four files.

## The shape

```php
public function update(OrderUpdateRequest $request, Order $order): RedirectResponse
{
    $this->authorize('update', $order);

    Orders::update($order, $request->validated(), $request->input('version'));

    return back()->with('status', 'Order updated.');
}
```

```php
class OrderUpdateRequest extends FormRequest
{
    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'status' => ['sometimes', 'required', Rule::enum(OrderStatus::class), $this->transitionRule()],
            'tracking_number' => ['sometimes', 'nullable', 'string', 'max:120'],
            'shipping_address' => ['sometimes', 'array'],
            'shipping_address.name' => ['required_with:shipping_address', 'string', 'max:255'],
            'shipping_address.line_1' => ['required_with:shipping_address', 'string', 'max:255'],
            // ...
            'version' => ['required', 'string'],
        ];
    }
}
```

One route replaces the pile:

```php
Route::put('/orders/{order}', [AdminOrderController::class, 'update'])->name('orders.update');
```

## Rules

- **Every field of the update request is `sometimes`.** That is what lets one method
  serve a single-field edit and a full-record save. See `laravel-controller-requests`
  for the `['sometimes', 'required', ...]` idiom.
- **The client sends only what changed.** A form that edits the tracking number posts
  `{tracking_number, version}` to the same URL as one that edits the status. Nothing on
  the frontend needs to know which endpoint owns which field.
- **Cross-field rules stay in the request**, not in the controller. A status transition
  check, an "address is only editable before shipping" guard, a "tracking number
  requires a shipped status" rule — all of these belong in `rules()`, `after()`, or a
  custom rule object on the update request. The controller stays three lines.
- **Nested groups nest.** A shipping address is `shipping_address.*`, validated with
  `required_with:shipping_address`, not seven top-level keys — so `sometimes` on the
  parent key means the whole block is optional as a unit.
- **The service takes the validated array**, and decides per key what to do with it.
  `Orders::update($order, $data)` dispatching internally beats the controller calling
  `updateStatus`, `updateTracking`, `updateShippingAddress` in sequence.
- **`store` and `destroy` keep their own methods.** This skill is about `update` only.

## The rare exceptions

Split a method out only when it is one of these. If you are arguing for a new
exception, you are almost certainly writing the anti-pattern.

- **It is not an update.** `resendConfirmation` sends an email; it writes nothing to the
  order. Side-effecting commands that change no attribute are their own POST route.
- **It writes a different model.** `storeNote` creates an `OrderNote`. That is `store`
  on a nested resource — `Route::post('/orders/{order}/notes', [OrderNoteController::class, 'store'])` —
  not an update of the order.
- **It needs a different permission.** Cancelling authorizes `cancel`, not `update`, so
  it cannot ride inside a method whose first line is `authorize('update')`. Prefer
  folding it in if the policy genuinely allows it; keep it separate if the policy
  genuinely does not.

Note that "the payload is complicated" and "the validation differs per field" are *not*
exceptions — `sometimes` plus `required_with` handle both.

## Why

Each split-out method looks small on its own, which is why the pattern spreads. The
cost is not in any one method, it is in the count: N properties produce N routes, N
requests, N authorize calls, N tests, and N places the frontend has to pick between.
Nothing tells a reader where "how do I change an order" is answered, because it is
answered five times.

Collapsing to one method makes the request class the single description of what an
order accepts, and makes multi-field edits — change the status *and* add tracking in
one atomic write, under one concurrency token — expressible at all. With split
endpoints they are two requests that can half-fail.

## The check

In `routes/`, look for two or more non-GET routes under the same `{model}` segment. In
`app/Http/Controllers/`, look for a public method on a resource controller that is
named after a column. Both are the anti-pattern unless they meet an exception above.
