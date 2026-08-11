---
name: laravel-inertia-react-structure
description: How to organise the frontend of a Laravel + Inertia + React app under resources/js — the common/modules/pages split, shadcn components in components/ui, casing rules, and React component conventions. Use when adding a React component, page, or hook; when deciding whether something belongs in common, modules, or a page folder; when naming a file or directory under resources/js; or when a component sits loose at the top of resources/js.
---

# Frontend structure for Inertia + React

Adapted from Spatie's "How to structure the frontend of a Laravel Inertia React
application". One deliberate change: shadcn components live in **`components/ui`**,
not a top-level `shadcn` directory — that is shadcn's own default alias
(`@/components/ui`) and changing it means every `shadcn add` fights the layout.

```
resources
├── css
│   └── app.css
└── js
    ├── common          ← generic, project-agnostic code & components
    ├── components/ui   ← auto-generated shadcn/ui components
    ├── modules         ← project-specific shared code & components
    ├── pages           ← Inertia-rendered pages
    └── app.tsx
```

## The four homes

| Directory | Holds | Test |
|---|---|---|
| `common` | Generic code and components. Could theoretically move to another project; only the styling is project-specific. | Would this make sense in an app about something else? |
| `modules` | Project-specific code shared across pages, or that warrants its own context outside a page. | Does it relate to a domain or feature of *this* app? |
| `pages` | Inertia page components, plus code scoped to one page or section. | Is it reached by a route? |
| `components/ui` | shadcn/ui output. | Did a generator write it? |

**`common` vs `modules`** is the only judgement call. Ask: *does it relate to a domain
or feature of our application?* If yes, it is a module. `Button` and `Card` are common;
`CategoryBadge` and `useCurrentUser` are modules.

Nothing sits loose at the top of `resources/js` except entry points (`app.tsx`,
`ssr.tsx`). A component directly in `resources/js` is this skill's bug.

## Inside common and modules

Both contain **one level of directories** that name a context. What goes in a context
is free-form until it grows, at which point organise it by type.

A small common module needs no ceremony:

```
resources/js/common/
    button/
        Button.tsx
    card/
        Card.tsx
        CardHeader.tsx
        CardContent.tsx
```

A substantial app module is organised by type:

```
resources/js/modules/agenda/
    components/
        Agenda.tsx
        ListView.tsx
        GridView.tsx
    contexts/
        AgendaContext.tsx
    helpers/
        parseDate.ts
    hooks/
        useAgenda.ts
    types.ts
```

The type directories are: `components`, `contexts`, `constants`, `helpers`, `hooks`,
`stores`.

Types go in a single `types.ts` per module. Only split into a `types/` directory when
that one file gets unwieldy.

`constants`, `helpers` and `hooks` may also sit at the top level of `common` for
low-level utilities that belong to no single context:

```
resources/js/common/
    helpers/
        parseDateFromServer.ts
    hooks/
        useIntersectionObserver.ts
```

## Pages

Page components mirror the URL structure and are **suffixed with `Page`**. A top-level
`layouts` directory holds global layouts; nested sections may have their own.

When a page needs partials or helpers, use the same type-based subdirectories, so that
**only page components sit directly in a page directory**.

```
resources/js/pages/
    layouts/
        Layout.tsx
    profile/
        layouts/
            ProfileLayout.tsx
        ProfilePage.tsx
    posts/
        components/
            PublishStatus.tsx
        helpers/
            generateSlug.ts
        CreatePostPage.tsx
        EditPostPage.tsx
        PostsIndexPage.tsx
    DashboardPage.tsx
```

A partial used by two different page sections has outgrown `pages` — move it to
`modules`.

## Casing

| Thing | Case | Example |
|---|---|---|
| Files exporting a component or React context | PascalCase | `PublishStatus.tsx` |
| All other files | camelCase | `generateSlug.ts`, `useAgenda.ts` |
| Directories | kebab-case | `product-groups/`, `common/button/` |

Directories are kebab-case **including** the ones Inertia resolves against, which means
the page name passed to `Inertia::render()` carries kebab directories and a PascalCase
file: `Inertia::render('admin/product-groups/EditProductGroupPage')`.

## shadcn components

Use shadcn/ui to kickstart a project rather than spending weeks on a component library
first, then migrate components into `common` as project needs emerge.

**Avoid changes to shadcn components beyond styling tweaks.** They are regenerated
output; treat them as vendor code. Their API — shadcn's and Radix's — is deliberately
low-level, which is right for building a UI library and too verbose for application
code:

```tsx
<Select>
    <SelectTrigger>
        <SelectValue placeholder="Select a fruit" />
    </SelectTrigger>
    <SelectContent>
        <SelectGroup>
            <SelectLabel>Fruits</SelectLabel>
            <SelectItem value="apple">Apple</SelectItem>
        </SelectGroup>
    </SelectContent>
</Select>
```

So wrap them in an app-level component in `common` that takes the props the app
actually has:

```tsx
<Select
    placeholder="Select a fruit"
    options={[
        { value: 'apple', label: 'Apple' },
        { value: 'banana', label: 'Banana' },
    ]}
/>
```

The wrapper lives in `common`; the generated primitive stays untouched in
`components/ui`.

## React component conventions

```tsx
import { PropsWithChildren } from 'react';

import { cn } from '@/common/helpers/cn';
import { PropsWithClassName } from '@/common/types/props';

type Props = PropsWithClassName<PropsWithChildren<{
    onClick?: () => void;
    type?: 'button' | 'submit';
}>>;

export function Button({ onClick, type, className, children }: Props) {
    return (
        <button type={type} onClick={onClick} className={cn(className)}>
            {children}
        </button>
    );
}
```

- **`function`, not `const`.** Components and functions read differently from
  variables at a glance. Arrow functions are for callbacks passed inline.
- **Named exports, one component per file.** `export default` is reserved for page
  components, because Inertia resolves them by filename.
- **No barrel files.** They look like a way to control a module's public surface, but
  in practice they are unenforceable and add indirection.
- **Two import blocks** — library imports, then application imports — enforced by
  `prettier-plugin-sort-imports`. Application imports use the `@/` alias, not relative
  paths that climb directories.
- **Props sorted alphabetically with `className` and `children` last.** Not enforced.
  UI components usually get those two from `PropsWithChildren` and a
  `PropsWithClassName` generic built on clsx.

## Stylesheets

Tailwind's utility-first approach suits component-based React, and a single
`resources/css/app.css` is usually enough. Only when a project has real styling needs,
split by scope:

```
resources/css/
    base/
        a.css
        h1.css
    components/
        button.css
        card.css
    utilities/
        typography.css
    app.css
```

## Multi-zone apps

An app with distinct sections — an admin and a client-facing app — gets an `apps`
directory. Typically one shared `common` for the design system, one global `modules`,
and app-specific `modules` alongside each app's pages.

```
resources
├── css
│   ├── admin/app.css
│   └── client/app.css
└── js
    ├── apps
    │   ├── admin
    │   │   ├── modules
    │   │   ├── pages
    │   │   └── app.tsx
    │   └── client
    │       ├── modules
    │       ├── pages
    │       └── app.tsx
    ├── common
    └── modules
```

Reach for this only when zones genuinely diverge. Two directories under `pages` are
cheaper than two entry points until the apps stop sharing a shell.

## Why the split earns its keep

On a backend-heavy team, `common` and `modules` are where the React expertise is
concentrated — the plumbing, state management and abstractions. `pages` is then mostly
forms, datatables and reusable patterns, which a backend-first developer can compose
without specialising in React. Anything that requires heavy lifting is a signal it
belongs in a module, not in a page.

## The check

- Nothing loose at the top of `resources/js` but entry points.
- Every directory kebab-case; every component file PascalCase; everything else
  camelCase.
- Every page component suffixed `Page`, with only page components sitting directly in
  a page directory.
- `components/ui` contains only generated shadcn output, unmodified beyond styling.
- No barrel files, no `export default` outside pages, no relative imports that climb.
