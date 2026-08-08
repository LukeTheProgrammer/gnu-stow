# claude

Personal Claude Code preferences — coding patterns that apply across all projects,
not the config of any one repo.

## Install

```sh
mkdir -p ~/.claude          # REQUIRED — see below
cd ~/dotfiles && stow claude
```

**`mkdir -p ~/.claude` is not optional.** `~/.claude` also holds machine-local state
(`history.jsonl`, `sessions/`, `projects/`, `shell-snapshots/`, `settings.json`). If
the directory does not exist when you stow, GNU Stow folds the tree and symlinks the
*entire* `~/.claude` into this repo — Claude Code then writes session logs and history
straight into your dotfiles. Creating the directory first forces stow to descend and
link only the leaves.

Re-run `stow claude` after adding a new top-level entry. New skills inside `skills/`
are picked up automatically, since `~/.claude/skills` is a single folded symlink.

Verify:

```sh
ls -ld ~/.claude ~/.claude/CLAUDE.md ~/.claude/skills
# ~/.claude          -> real directory
# ~/.claude/CLAUDE.md -> symlink into ~/dotfiles/claude/
# ~/.claude/skills    -> symlink into ~/dotfiles/claude/
```

## What lives where

| | |
|---|---|
| `.claude/CLAUDE.md` | Always in context, every session. One-line imperative rules. |
| `.claude/skills/<name>/SKILL.md` | Loaded on demand, only when relevant. |

**Split rule:** one line and always true → `CLAUDE.md`. Needs examples or has
exceptions → a skill.

Project-specific facts (framework versions, build commands, deploy quirks) do **not**
belong here — those go in the project's own checked-in `CLAUDE.md`.

## Writing a skill

```markdown
---
name: laravel-conventions
description: <when this applies — be specific>
---

...rationale, a real before/after pair, explicit exceptions...
```

The `description` is the *only* part always in context, and it alone decides whether
the body ever loads. A vague description means a skill that silently never fires.
Prefer one skill per domain (`laravel-conventions`, `react-inertia-conventions`,
`typescript-style`) over one skill per rule.
