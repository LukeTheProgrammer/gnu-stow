# shell

Shell config shared between bash and zsh, plus the helper scripts that keep the
other stow packages honest.

## Install

```sh
stow -d ~/dotfiles -t ~ shell
```

Then, once: `restow shell` and everything else.

## Layout

| | |
|---|---|
| `.shell_aliases` | Aliases shared by both shells. POSIX only — no bashisms, no zsh-isms. |
| `.local/bin/restow` | Safe relink of a stow package. |
| `.local/bin/restow.check` | Report what each tracked file currently links to. |

`.shell_aliases` is sourced by `wsl/.bash_aliases` and `zsh/.zsh_aliases`, which hold
only what is genuinely shell-specific. Anything longer than a line or two belongs in
`.local/bin/` as an executable, not in the alias file.

`~/.local/bin` is already on `PATH` (see `wsl/.bashrc`), so the scripts are ordinary
commands — no alias needed. They are separate processes and so cannot change the
calling shell's environment; that is fine for what they do, but it does mean a future
helper that needs to `cd` or export a variable must be a function in `.shell_aliases`
instead.

## restow

```sh
restow claude          # unstow, prune empty dirs, relink
restow claude shell    # several at once; stops at the first failure
restow.check claude    # link / fold / FILE / MISS per tracked file
```

`restow` exists because three stow behaviours are easy to get wrong by hand:

1. **Relative `-d`.** `cd ~/dotfiles && stow claude` emits `BUG in find_stowed_path?
   Absolute/relative mismatch` for every symlink in `$HOME` pointing outside it — on
   WSL, every `/mnt/c/...` link. Harmless, but it buries real conflict messages.
2. **Stow without unstow** leaves dangling symlinks when a file is renamed or deleted.
3. **Lost folding.** If a real directory exists at stow time, stow descends and links
   leaf-by-leaf. New files then need a re-stow to appear, and a subdirectory added
   inside an already-linked directory is silently missed — a skill with a `reference/`
   folder ships without it.

Pruning is the only destructive step, and it is deliberately narrow: it touches a
directory only if the package defines it, it sits *below* the package's top-level
entries, and it is already empty. The top-level exclusion matters — pruning `~/.claude`
itself would let stow fold the whole directory into one symlink, and Claude Code would
then write `history.jsonl` and session logs into this repo.

`restow.check` exits non-zero if anything is `FILE` or `MISS`. `FILE` is the one to act
on: an application replaced a symlink with its own copy, so edits there no longer reach
the repo and sync has silently stopped.

## Adding a machine-specific override

Keep it out of `.shell_aliases`. Put it in the per-shell file, or guard it:

```sh
[ -f ~/.shell_aliases.local ] && . ~/.shell_aliases.local
```
