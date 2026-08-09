---
name: laravel-authorization-architecture
description: Every authorization decision runs through a policy, the policy checks a named permission constant, and the permission is granted to a role — no inline ownership helpers, role comparisons, or abort_unless checks anywhere in app/. For projects using spatie/laravel-permission; if the package is absent, recommend installing it and stop. Use when adding an authorization check, reviewing a controller for access control, or auditing app/ for ad-hoc permission logic.
---

# Authorization: policy → permission → role

## Precondition

This skill only describes projects built on `spatie/laravel-permission`.

```bash
grep -q 'spatie/laravel-permission' composer.json && echo present
```

If it is not present, **do not apply any of the rules below and do not hand-roll an
equivalent**. Say that the project needs the package, give the install steps, and
stop:

```bash
composer require spatie/laravel-permission
php artisan vendor:publish --provider="Spatie\Permission\PermissionServiceProvider"
php artisan migrate
```

…plus `use HasRoles;` on the `User` model. Once it is installed, the rest applies.

## The chain

Every authorization decision is the same four links, and each link has exactly one
home:

```
app/Enums/Permissions.php      ← the name of the action, as an enum case
app/Enums/Roles.php            ← which roles hold which permissions
app/Policies/<Model>Policy.php ← the decision, expressed as a permission check
controller / route / view      ← authorize(), can(), or @can — never the decision itself
```

**1. The permission** — a **string-backed enum**, one case per action, values named
`area.verb`. Nothing else in the app ever writes a permission as a string literal.

```php
enum Permissions: string
{
    case CATEGORIES_UPDATE = 'categories.update';

    /** Separate from ORDERS_UPDATE because cancelling issues a refund. */
    case ORDERS_CANCEL = 'orders.cancel';

    /** @return list<string> */
    public static function values(): array
    {
        return array_column(self::cases(), 'value');
    }
}
```

**2. The role** — also a string-backed enum, with the grant expressed as a method on
it rather than a lookup table beside it. A superuser role is computed from
`Permissions::values()`, never hand-listed, so a new permission is picked up on the
next seed.

```php
enum Roles: string
{
    case SUPER_ADMIN = 'super-admin';

    /** @return list<string> */
    public function permissions(): array
    {
        return match ($this) {
            self::SUPER_ADMIN => Permissions::values(),
            // …
        };
    }
}
```

The seeder walks the cases and is idempotent, so re-running after a new permission is
added is safe. It is the one file where the enums and the package's own models meet —
and because the enums are plural and the models are singular, both are named plainly,
with no aliasing:

```php
use App\Enums\Roles;
use Spatie\Permission\Models\Role;

foreach (Roles::cases() as $role) {
    Role::findOrCreate($role->value, 'web')->syncPermissions($role->permissions());
}
```

**3. The policy** — one class per model, methods named for the ability, each
delegating to `$user->can()` with an enum case.

```php
class CategoryPolicy
{
    public function update(User $user, Category $category): bool
    {
        return $user->can(Permissions::CATEGORIES_UPDATE->value);
    }
}
```

**4. The call site** — asks the policy and nothing else.

```php
$this->authorize('update', $category);
```

## Rules

- **Every authorization check goes through a policy.** If a method decides who may do
  something, that decision belongs in a policy method, reached via `authorize()`,
  `Gate::allows()`, `$user->can($model)`, or a `can:` route middleware.
- **Never write a private `authorize*()` helper on a controller.** A method like
  `authorizeAddress()` doing `abort_unless($address->user_id === Auth::id(), 403)` is
  the exact thing this skill removes: it is a policy that has been inlined, so it is
  invisible to `Gate`, untestable on its own, and silently diverges from the same
  check made elsewhere. Move the body into `AddressPolicy::update()` and call
  `$this->authorize('update', $address)`.
- **Never compare roles to make a decision.** `$user->role === UserRole::ADMIN`,
  `$user->hasRole('admin')`, and `role:admin` middleware all hard-code today's role
  layout into the call site. Check the *permission* — that is what makes a new role
  a seeder change instead of a grep. Roles are for *granting*, permissions are for
  *checking*.
- **Never pass a permission string literal to `can()`.** Always `Permissions::CASE->value`,
  so the seeder and the check cannot drift apart. Gate abilities are strings, so the
  `->value` is explicit at the call site rather than relying on the framework to
  unwrap the enum.
- **`Permissions` and `Roles` are enums in `app/Enums`, not constant-holder classes,
  and their names are plural.** The plural is what keeps them clear of the package's
  singular `Spatie\Permission\Models\{Permission,Role}`: a file may import the enum
  and the model together — the seeder and the grant/revoke commands do — and neither
  needs an alias.
- **Never authorize inside a form request.** When an action takes a
  `FormRequest`, leave `authorize()` off the request class entirely and call
  `$this->authorize(...)` in the controller method. The request's job is the shape of
  the input; the controller's is who may act. Splitting them across two files hides
  half the answer to "who can do this?", and a request's `authorize()` returning
  `false` yields a bare 403 with no policy behind it — untestable via `Gate`, and
  invisible to the audit below.
- **Ownership is a policy too.** "Only the owner may edit this" is
  `return $user->id === $address->user_id;` inside the policy method — with a
  permission check `||`'d in if staff may also act on it. It is not a reason to skip
  the policy.
- `abort_unless()` in a controller is fine for things that are **not** authorization:
  a record-type filter (`abort_unless($user->role === UserRole::CUSTOMER, 404)` to
  hide staff accounts from a customer endpoint), or a nested-route integrity check
  (`abort_unless($image->product_id === $product->id, 404)`). The tell is the status
  code and the question: 404 "this isn't the thing you asked for" is routing, 403
  "you may not" is authorization and belongs in a policy.
- A policy that grants everything to a superuser uses `before()`, once, rather than a
  role check repeated in every method.
- New guarded action → add the constant, add it to the role definitions, add the
  policy method, then call `authorize()`. Re-run the role seeder.

## Why

Authorization spread across controllers cannot be reviewed. The question "who can
cancel an order?" should have one answer readable in one file; when the check is an
`abort_unless` in a controller, an `if` in a Blade/Inertia view, and a role
comparison in a job, the answer is "whatever those three happen to agree on today" —
and they drift, always in the permissive direction.

Routing every decision through a policy also means the framework can ask it: route
middleware, `Gate::allows()` in a view, and a test can all reach the same method.
Naming permissions rather than roles is what keeps the layout changeable — adding a
"support agent" who may refund but not edit products is a seeder change, and no
call site moves.

## The audit

Sweep `app/` for decisions that never reached a policy:

```bash
grep -rn "abort_unless\|abort_if" app/                 # 403s here are inlined policies
grep -rn "hasRole\|hasAnyRole\|->role ===" app/        # role comparisons
grep -rn "private function authorize" app/Http         # controller-local policies
grep -rn "can('\|can(\"" app/ resources/               # literal permission strings
grep -rn "Gate::define" app/                           # inline gates that should be policies
grep -rn "function authorize" app/Http/Requests        # authorization stranded in form requests
```

For each hit: 403 or a decision → move it into the model's policy as a permission
check, add the constant and the role grant if the permission is new, and replace the
call site with `authorize()`. 404 record-type and nested-route checks stay put.
