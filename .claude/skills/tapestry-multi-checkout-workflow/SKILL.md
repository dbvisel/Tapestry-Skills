---
name: tapestry-multi-checkout-workflow
description: Work across several open tapestry-project PRs at once by keeping one checkout (or git worktree) per PR, each intentionally left parked on its own branch instead of main — verified real gotchas on remote-naming inconsistency between checkouts, a worktree's .git living in a different directory than its working tree, and syncing a fork's main without destroying its own commits
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["multiple checkouts", "several tapestry-project directories", "which branch is this checkout on", "switch to the X branch", "parked on a PR branch"]
  - keywords: ["git worktree", "worktree .git location", "worktree remote naming", "git branch --show-current", "git remote -v"]
  - keywords: ["origin means different things", "remote naming inconsistent", "fork main not a clean mirror", "sync fork main with upstream"]
last_verified: 2026-09-16
---

Working on several `tapestry-project` PRs in the same review cycle means keeping
several real checkouts (or `git worktree`s) on disk at once, **each intentionally left
on a specific PR's branch rather than `main`** — not a temporary state to "clean up,"
but the actual working setup for as long as that PR is still under review. Verified
against a real workspace holding three such checkouts simultaneously, across two
different forks and three different PRs.

## When to use this skill

- A workspace has more than one `tapestry-project` checkout on disk
- Told to "switch to the X branch" or "switch over to the Y PR" and there's more than
  one checkout to consider
- About to run any `git` command in a `tapestry-project` checkout you haven't
  worked in yet this session
- Setting up a new checkout/worktree for a new PR without disturbing existing ones

## The core discipline: verify, don't assume

**Check `git branch --show-current` before assuming which PR a checkout represents.**
A checkout's directory name is a hint, not a guarantee — the actual state is whatever
branch is currently checked out, and that can drift from what a note or your own
memory says it was last time.

**Check `git remote -v` before assuming what a remote name points to.** This is the
single most likely mistake in this setup: **`origin` does not mean the same thing in
every checkout.** Verified real case — two checkouts of the same repo, both cloned
from GitHub normally, ended up with opposite conventions:

- Checkout A: `origin` = the upstream repo PRs are opened against, a separate remote
  name (e.g. `dbvisel`) = the personal fork branches get pushed to.
- Checkout B: `origin` = the personal fork (what you push to), a separate remote name
  (e.g. `upstream`) = the repo PRs go against.

Neither is "wrong" — they just reflect how each checkout happened to get set up
(which URL `git clone` was pointed at first). Running a `push`/`fetch` against
`origin` without checking which checkout you're in risks pushing to the wrong place
entirely. Get in the habit of resolving the actual URL (`git remote get-url origin`)
rather than trusting the name.

## Worktrees add one more real gotcha: where `.git` actually lives

A `git worktree add <path> <branch>` checkout is not a normal clone — its `.git` is a
file (not a directory) pointing back into the **original checkout's** `.git/worktrees/`
directory, which can be a completely different location on disk than the worktree's
own working directory. Two consequences, both verified:

- **Sandboxed tool execution can block `git` commands in a worktree** if the sandbox
  only allows writes under the worktree's own directory tree — the actual git metadata
  it needs to touch lives elsewhere. If a `git` command in a worktree fails with a
  permissions-shaped error, that's the likely cause; a broader filesystem allowance
  (or a sandbox bypass, if your tooling supports one) is the fix, not a git problem to
  troubleshoot.
- **A worktree inherits its remote configuration from whichever checkout it was
  created inside**, not from any workspace-wide convention — so the "which name means
  what" problem above applies *especially* to worktrees, and isn't predictable from
  the other checkouts' pattern. Always verify fresh.

## Don't switch a checkout off its assigned branch

If a checkout is parked on a PR's branch, leave it there after finishing a task —
including after pushing fixes, replying to review comments, and resolving threads.
The PR is very likely to get another review round, and the checkout being ready and
un-drifted (no stray `git checkout main`, no accidentally-left uncommitted changes
from a different task) is what makes jumping back into it later fast. Only switch a
checkout's branch when explicitly told to (the PR merged/closed, or the user asks for
something else in that same directory).

## Syncing a fork's own `main` is not a clean mirror operation

If one remote is a personal fork used to push PR branches from, its `main` branch can
carry real, fork-specific commits on top of upstream's `main` (a different local-dev
installer, environment-specific config, etc.) — **don't fast-forward or force-push it
to match upstream**, which would silently destroy those commits. Sync it with a real
merge (upstream's `main` merged into the fork's `main`, preserving the fork's own
history) instead, and do this in a disposable scratch worktree/clone rather than
inside whichever checkout is mid-review, so a sync operation can't disturb in-progress
work if something goes wrong.

## Orienting when told to "switch to the X branch/PR"

In this setup, that instruction almost always means **change which checkout directory
you operate in**, not run `git checkout` inside the one you're already in — the target
checkout is very likely already sitting on that exact branch, parked there from a
previous session. Find it by:

1. Checking whatever notes/memory exist for a checkout-to-PR mapping first — but treat
   it as a starting hint, not ground truth, since a new checkout can appear between
   sessions without the notes being updated.
2. If nothing points to a specific directory, or the mapping looks stale, list
   candidate `tapestry-project` directories and check each one's `git branch
   --show-current` and `git log -1` to confirm which PR/branch it's actually on —
   cross-reference against `gh pr list` if the branch name alone is ambiguous.
3. Once there, re-verify remotes (`git remote -v`) before pushing or fetching —
   see above.

## Guardrails

1. **A checkout's directory name and a stale note are hints, not facts.** Verify
   `git branch --show-current` and `git remote -v` fresh at the start of work in any
   checkout you haven't touched yet this session.
2. **Never assume `origin` is the same kind of remote (fork vs. upstream) across
   checkouts.** Resolve the actual URL when it matters, especially before a push.
3. **A worktree's `.git` metadata can live in a different directory than its working
   tree** — expect this to interact with sandboxed tool execution, and expect its
   remote config to follow whichever checkout it was created from, not a
   workspace-wide pattern.
4. **Don't switch a parked checkout back to `main`** once a task is done — leave it on
   the PR branch for the next review round, unless told the PR is merged/closed or
   asked to switch it for something else.
5. **A fork's `main` can carry real commits upstream's `main` doesn't have.** Sync with
   a merge, in a scratch location, never a fast-forward/force-push against a checkout
   holding in-progress work.
