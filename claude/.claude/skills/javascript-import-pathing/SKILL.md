---
name: javascript-import-pathing
description: Every import of application code in a .js/.jsx/.ts/.tsx file uses the fully qualified alias path (`@/...`), never a relative path — not `../../common/button/Button`, and not `./Sibling` either. Use when writing or editing any import statement, when moving or renaming a module, or when reviewing a file that imports from `./` or `../`.
---

# Import by alias, never by relative path

Application code is always imported by its full path from the project root, through
the `@` alias:

```ts
import { Button } from '@/common/button/Button';
import { formatCurrency } from '@/common/helpers/formatCurrency';
import { CouponForm } from '@/pages/admin/coupons/components/CouponForm';
```

Never:

```ts
import { Button } from '../../common/button/Button';   // ✗ climbs
import { CouponForm } from './components/CouponForm';  // ✗ same directory is still relative
import { format } from './format';                     // ✗ sibling is still relative
```

**Same-directory imports are not an exception.** `./Sibling` is the most common way
this rule gets broken, because it looks harmless. It is the same problem: the import
describes where the file is *standing* rather than what it is *importing*.

## Why

- **Moving a file becomes a rename, not a rewrite.** A module's imports keep working
  wherever the file lands, and every importer keeps working when the *imported* file
  moves — only the one path that actually changed needs updating.
- **The same module is spelled the same way everywhere.** `@/common/helpers/date` is
  one greppable string. As a mix of `./date`, `../helpers/date` and
  `../../common/helpers/date`, it is three, and a find-and-replace across a rename
  silently misses some.
- **No depth arithmetic.** `../../../` is a fact about the reader's location, not
  about the dependency, and it is wrong the moment either file moves.

## What this rule does not cover

- **npm packages keep bare specifiers**: `import { useForm } from '@inertiajs/react'`.
  Unchanged — the rule is about application code.
- **Paths outside the alias root** (a vendor directory the alias does not reach) may
  have no aliased form. Those are the only legitimate relative imports; there should
  be very few, and each is worth a comment saying why.

## Setup

The alias must resolve in **both** the type checker and the bundler, or one will pass
while the other fails at build time:

```jsonc
// tsconfig.json
"paths": { "@/*": ["./resources/js/*"] }
```

```js
// vite.config.js
resolve: { alias: { '@': path.resolve(__dirname, 'resources/js') } }
```

A Laravel + Vite project using `laravel-vite-plugin` usually has the bundler side
already; confirm it rather than assuming.

## Enforcement

Make the linter own this instead of code review:

```js
// eslint.config.js
'no-restricted-imports': ['error', {
    patterns: [{
        group: ['./*', '../*'],
        message: 'Import application code by its full alias path (@/...), not relatively.',
    }],
}],
```

Add an `ignores` entry for any file that genuinely needs a relative path out of the
alias root.

## The check

`grep -rn "from '\.\.\?/" <source dir>` returns nothing, except for documented
imports that reach outside the alias root.
