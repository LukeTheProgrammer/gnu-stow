---
name: laravel-controller-requests
description: When a controller method validates more than three keys, the rules move into a form request in app/Http/Requests — the controller type-hints it and never calls $request->validate(). Use when writing or editing a controller action that validates input, when a validate() call grows past three keys, or when adding a new form request.
---

# Validation belongs in a form request

A controller action reads as a sequence of steps: take validated input, do the work,
return a response. Validation rules are not one of those steps — once there are more
than three of them they are a block of configuration sitting in the middle of the
method.

**Rule: more than three validated keys → a form request.** Three or fewer may stay
inline as `$request->validate([...])`.

```
app/Http/Requests/<Area>/<Model><Action>Request.php   ← the rules
app/Http/Requests/Concerns/<Thing>Rules.php           ← rules shared by two requests
```

## The shape

```php
namespace App\Http\Requests\Admin;

use App\Enums\CouponType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CouponStoreRequest extends FormRequest
{
    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'code' => ['required', 'string', 'max:60', Rule::unique('coupons', 'code')],
            'type' => ['required', Rule::enum(CouponType::class)],
            'value' => ['nullable', 'numeric', 'min:0'],
            'expires_at' => ['nullable', 'date'],
        ];
    }
}
```

The controller type-hints it and uses `validated()`:

```php
public function store(CouponStoreRequest $request): RedirectResponse
{
    Coupons::create($request->validated());

    return to_route('admin.coupons.index');
}
```

## Naming and placement

- `<Model><Action>Request` — `ProductStoreRequest`, `ProductUpdateRequest`,
  `OrderCancelRequest`. Store and update are **separate** requests, not one class
  branching on `$this->method()`; their rules genuinely differ (unique-ignoring-self,
  `sometimes`, fields that cannot change after creation).
- For an action that is not CRUD, name it for the action:
  `OrderTrackingRequest`, `ProductVariantOptionsRequest`.
- Namespace mirrors the controller's: an admin controller's requests live in
  `app/Http/Requests/Admin/`, auth in `Auth/`, storefront at the top level.

## Rules

- **Never `$request->validate()` with more than three keys in a controller.** That is
  the trigger for this skill.
- **Never re-validate in the controller** after type-hinting a form request, and never
  read `$request->input()` for a key the request already validated — use
  `validated()`, or the typed accessor the request exposes.
- Rules use **array syntax**, not pipe strings: `['required', 'string']`, not
  `'required|string'`. Rule objects (`Rule::enum`, `Rule::unique`) compose with it.
- `rules()` carries the `@return array<string, mixed>` docblock; the method itself is
  typed `: array`.
- Normalization goes in `prepareForValidation()` on the request (upcasing a coupon
  code, nulling an empty rich-text field), not in the controller before the call.
- Authorization that is about *this request's data* may go in `authorize()`; policy
  checks stay in the controller or middleware where they are visible.
- **An update request's fields are all optional.** Prefix every rule with `sometimes`
  so a caller can change one field without resubmitting the whole record — but keep
  the `required`/`nullable` behind it, so an omitted key is left alone while a key
  that *is* sent still cannot be blanked out if the record needs it:
  `['sometimes', 'required', 'string', 'max:255']`.
- Because of that, store and update rarely hold the same array, and each writes its
  own `rules()` in full. Duplication between the two is expected and fine; it is what
  lets the update rules relax independently of the store rules.
- Reach for a trait in `app/Http/Requests/Concerns/` only when the shared rules are a
  *fragment* of a larger request rather than the whole of it — a shipping address
  block that appears inside both a checkout request and an admin correction, where the
  two requests are otherwise unrelated. Do not have one form request extend another.

## Why

Inline `validate()` calls are the most common way a controller stops being readable.
The rules array is longer than the logic around it, so the method's actual work gets
buried, and the same field ends up validated three slightly different ways across
store, update, and an API endpoint — nowhere to look for "what is a valid coupon."

Moving it out gives one file per shape of accepted input. The controller signature
then states what it accepts, which is also what makes the endpoint testable: the
request can be unit-tested against rule sets without exercising the controller.

## Adding one

1. `./vendor/bin/sail artisan make:request Admin/CouponStoreRequest`
2. Move the rules array in verbatim; convert pipe strings to arrays while moving.
3. Move any pre-validation munging into `prepareForValidation()`.
4. Type-hint the request in the controller, delete the `validate()` call, and use
   `$request->validated()`.

## The check

Grep controllers for `->validate(`. Every hit should have three or fewer keys in its
array. Anything longer is a form request that has not been extracted yet.
