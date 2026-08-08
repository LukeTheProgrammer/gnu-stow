# claude

Personal Claude Code preferences — coding patterns that apply across all projects,
not the config of any one repo.

## Install

```sh
mkdir -p ~/.claude          # REQUIRED — see below
stow -d ~/dotfiles -t ~ claude
```

**`mkdir -p ~/.claude` is not optional.** `~/.claude` also holds machine-local state
(`history.jsonl`, `sessions/`, `projects/`, `shell-snapshots/`). If the directory does
not exist when you stow, GNU Stow folds the tree and symlinks the *entire* `~/.claude`
into this repo — Claude Code then writes session logs and history straight into your
dotfiles. Creating the directory first forces stow to descend and link only the leaves.

After the first install, use the `restow` helper from the `shell` package (installed to
`~/.local/bin`) instead of calling stow directly — it handles the pitfalls below
automatically:

```sh
restow claude        # unstow, prune empty dirs, relink
restow.check claude  # show what each tracked file currently links to
```

**Always pass `-d ~/dotfiles` (absolute).** Running `cd ~/dotfiles && stow claude` with
a relative stow dir makes stow emit `BUG in find_stowed_path? Absolute/relative
mismatch` for every symlink in `$HOME` that points outside it — on WSL that means every
`/mnt/c/...` link. Harmless, but it buries real conflict messages.

Re-run after adding a new **top-level** entry (a new file directly under `.claude/`).
New skills need no re-stow: `~/.claude/skills` is a single folded symlink, so anything
added under `claude/.claude/skills/` in this repo appears immediately.

That folding is load-bearing and easy to lose. If a real `~/.claude/skills/` directory
ever exists at stow time, stow descends and links each `SKILL.md` individually — then
every new skill needs a re-stow, and a skill with a `reference/` subdirectory silently
ships without it. To restore folding, unstow, remove the empty leftover directories,
and stow again — which is exactly what `restow claude` does.

Verify:

```sh
ls -ld ~/.claude ~/.claude/CLAUDE.md ~/.claude/skills ~/.claude/settings.json
# ~/.claude             -> real directory
# everything else       -> symlink into ~/dotfiles/claude/
```

## What lives where

| | |
|---|---|
| `.claude/CLAUDE.md` | Always in context, every session. One-line imperative rules. |
| `.claude/skills/<name>/SKILL.md` | Loaded on demand, only when relevant. |
| `.claude/settings.json` | Model, effort level, TUI mode, enabled plugins. |

**Split rule:** one line and always true → `CLAUDE.md`. Needs examples or has
exceptions → a skill.

Project-specific facts (framework versions, build commands, deploy quirks) do **not**
belong here — those go in the project's own checked-in `CLAUDE.md`.

Skills here must be **project-agnostic** — they load on any machine, against any repo.
A skill that names one codebase or asserts a path that only exists locally is a bug:
it goes stale the moment that repo is refactored, and it is useless on a machine that
doesn't have it. Concrete vendors (Stripe, Mailjet) are fine; concrete repos are not.

### Deliberately not tracked

- **`settings.local.json`** — machine-local overrides. Claude Code merges it over
  `settings.json`, so per-PC differences belong here rather than as edits to the
  shared file. Keep it out of the repo.
- **`plugins/`** — 53 MB of git clones and caches with absolute paths baked in.
  `enabledPlugins` in `settings.json` carries the intent; the clones re-fetch. On a
  new machine, add the marketplace once and Claude Code restores the rest:
  ```sh
  claude  # then: /plugin marketplace add anthropics/claude-plugins-official
  ```
- **`.credentials.json`** — auth tokens. Never commit; `claude` re-authenticates.
- **Session state** — `history.jsonl`, `projects/`, `sessions/`, `file-history/`,
  `shell-snapshots/`, `session-env/`, `debug/`, `plans/`, `todos/`, `statsig/`.
  Per-machine by nature.

`settings.json` is written by Claude Code itself (`/config`, toggling a plugin). Those
writes land in this repo as a normal diff, which is the point — but if a future version
writes it via replace-rather-than-edit, the symlink becomes a regular file and sync
silently stops. `ls -l ~/.claude/settings.json` should always show a symlink.

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
