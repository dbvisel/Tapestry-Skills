# Script Audit & Compatibility Guidelines

Guidelines for the shell (`.sh`) and Python (`.py`) scripts bundled with skills in this
repository. The goal: scripts that are **descriptive, safe, portable, and gracefully
handle invocation with no arguments** — modeled on
[Wikipedia-AI-Skills](https://github.com/fuzheado/Wikipedia-AI-Skills)'s guidelines doc
of the same name, adapted to this repo's actual scale (six scripts as of the audit
below, not dozens) and idioms (Docker/Postgres orchestration, a standalone zip format,
no external network APIs). Don't assume the two documents stay identical — re-derive
from this repo's real scripts if they diverge further.

---

## 1. Zero-Argument Handling

**Shell scripts:** either give every argument a sensible default and document that
zero-arg behavior explicitly (`manage-tapestry-visibility.sh` lists everything and
prompts; `backup-tapestry.sh` backs up with defaults; `setup.sh` runs the interactive
installer), or guard required arguments and fail with usage on stderr:

```bash
if [ -z "$REQUIRED_ARG" ]; then
  echo "error: --required-arg is required" >&2
  usage
  exit 1
fi
```

Either way, support `-h`/`--help` explicitly — don't rely on the zero-arg case alone to
teach usage, since a script with all-defaulting args (the common case here) will
otherwise just *run* on `-h`/`--help` too unless that's checked first.

**Python scripts:** use `argparse` with **required positional arguments** wherever the
script can't do anything useful without them — `argparse` itself then prints usage and
exits nonzero on bare invocation, no extra guard needed. The `len(sys.argv) == 1` guard
from the upstream guidelines only matters when *every* argument has a `default=`, which
hasn't come up in this repo yet; add it if a future script gets there.

### Current audit (2026-08-19)

| Script | Skill | Zero-args behavior | `--help`/`-h` | Status |
|---|---|---|---|---|
| `manage-tapestry-visibility.sh` | `tapestry-visibility` | Lists everything, prompts (intentional) | ✅ Yes (added in this audit) | Pass |
| `backup-tapestry.sh` | `tapestry-backups` | Runs with defaults (intentional) | ✅ Yes | Pass |
| `setup.sh` | `tapestry-local-dev-environment` | Runs interactive installer (intentional) | ✅ Yes | Pass |
| `package-standalone-viewer.sh` | `tapestry-standalone-viewer` | Errors with usage (`--zip`/`--output` required) | ✅ Yes | Pass |
| `build-tapestry-zip.py` | `tapestry-zip-authoring` | `argparse` prints usage, exits 2 (required positionals) | ✅ Yes (via `-h`) | Pass |
| `analyze-tapestry-zip.py` | `tapestry-zip-analysis` | `argparse` prints usage, exits 2 (required positional) | ✅ Yes (via `-h`) | Pass |

`manage-tapestry-visibility.sh` was the one real gap found by this audit — it had no
`-h`/`--help` case despite the other three shell scripts all having one. Fixed as part
of writing this doc; re-run this table's logic (`grep -n "help\|# -eq 0"` per script)
before trusting it as still current.

---

## 2. Bash Version Portability (macOS ships bash 3.2)

`#!/usr/bin/env bash` resolves to bash 3.2 on a stock macOS install (Apple stopped
shipping newer bash over its GPLv3 licensing) unless the user has a Homebrew bash
ahead of it on `PATH`. Every script in this repo is developed and reviewed on macOS at
least some of the time, so this is a real, current constraint. Avoid:

| Feature | Problem | Use instead |
|---|---|---|
| `declare -A` (associative arrays) | bash 4+ only | `case "$key" in val) ... ;; esac`, or delegate to Python |
| `${var,,}` / `${var^^}` (case change) | bash 4+ only | `tr '[:upper:]' '[:lower:]'` |
| `mapfile` / `readarray` | bash 4+ only | `while IFS= read -r line; do ... done < <(...)` (already the pattern `manage-tapestry-visibility.sh` uses) |
| `printf -v var` | bash 4+ only | `var=$(printf ...)` |

None of the six scripts currently use any bash 4+ feature — keep it that way rather than
adding a version-check guard; this repo's scripts are short enough that avoiding the
feature outright is simpler than gating on `${BASH_VERSINFO}`.

**A sharper, more common trap than bash version: BSD vs. GNU coreutils on macOS.**
Encountered directly in this repo's own development (not hypothetical): `sed -i` needs
a (possibly empty) extension argument on macOS's BSD `sed` (`sed -i '' 's/a/b/'`) but
GNU `sed` on Linux treats a bare `-i` as in-place with no backup and errors on the
empty-string form. If a script needs `sed -i` at all, prefer branching or using `perl
-pi` instead, which behaves identically on both. Same story for `date -v-30d` (macOS)
vs. `date -d '30 days ago'` (GNU) if date arithmetic is ever needed:

```bash
DATE=$(date -v-30d +%Y%m%d 2>/dev/null || date -d '30 days ago' +%Y%m%d)
```

None of the six scripts do in-place `sed` editing or date arithmetic today, but the
Python-based skills (`tapestry-zip-authoring`/`tapestry-zip-analysis`) sidestep this
class of problem entirely by using Python's stdlib (`pathlib`, `re`, `zipfile`) instead
of shelling out to `sed`/`date` — prefer that when a new script has the choice.

---

## 3. Usage Message Best Practices

Every usage message should answer: what does it do, what arguments does it take, and
show 1–3 realistic examples. The pattern already used by
`package-standalone-viewer.sh`/`backup-tapestry.sh`/`setup.sh` — a comment block at the
top of the file, surfaced via `-h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0
;;` — keeps the usage text and the help output from drifting apart, since there's only
one copy to maintain. Prefer that over a separate `usage()` function with duplicated
text, unless the script is complex enough to need conditional help sections.

For Python scripts, `argparse`'s own `description=__doc__` (used by both
`build-tapestry-zip.py` and `analyze-tapestry-zip.py`) gets the same benefit: the
module docstring *is* the `--help` output, so there's one source of truth.

---

## 4. Additional Recommendations

- **Errors and diagnostics to stderr; only real output to stdout.** Already the
  convention in every script here (`analyze-tapestry-zip.py`'s human-readable report is
  the exception that's meant to print to stdout — it's the primary output, not a
  diagnostic, and `--json` gives a machine-readable alternative on the same stream).
- **`set -euo pipefail` at the top of every bash script.** All four already do this —
  keep it non-negotiable for new ones.
- **Quote all variable expansions**, prefer `$(...)` over backticks, `printf` over
  `echo` when output needs to be exact.
- **Redirect a wrapped interactive command's stdin from `/dev/null` if the wrapping
  script itself reads from stdin.** `manage-tapestry-visibility.sh` does this for
  `docker compose exec` specifically because the script's own `read -r -p` prompts need
  real stdin, and `docker compose exec` would otherwise happily drain it. Anything that
  wraps another process while also prompting the user should check for this.
- **Prefer stdlib-only Python with no third-party dependencies** for any script whose
  whole point is being usable without a repo checkout or installed dependencies — this
  is why `build-tapestry-zip.py`/`analyze-tapestry-zip.py` use only `zipfile`/`json`/
  `argparse`/etc. from the standard library. Scripts that inherently orchestrate
  Docker/Postgres/npm (`backup-tapestry.sh`, `setup.sh`,
  `manage-tapestry-visibility.sh`) don't need this constraint — they already assume a
  real installation to operate on.
- **Bundled scripts live under `scripts/`; non-executable templates/configs live
  under `assets/`; prose supporting docs live under `references/`.** Don't put a
  `.env.sample`, Dockerfile, or compose file in `scripts/` just because a script in
  the same skill reads it — `tapestry-local-dev-environment`'s `setup.sh` is the
  script; the `.env.sample`/`docker-compose.minio.yml`/`Dockerfile.client-minio` it
  reads are `assets/`, since none of them are code that runs. (Two real
  inconsistencies were fixed by this audit: `manage-tapestry-visibility.sh` lived
  under `references/` instead of `scripts/`, and those three config files lived
  under `scripts/` instead of `assets/`.)
- **Temp files, if any are ever needed**: `mktemp` + `trap '...' EXIT` in bash,
  `tempfile.NamedTemporaryFile`/`tempfile.mkdtemp` in Python. No script currently
  creates temp files, but this is the pattern to reach for for when one does.

---

## 5. Checklist for New Scripts

- [ ] `set -euo pipefail` (shell) or `argparse` with required args, or an explicit
      `len(sys.argv) == 1` guard if every arg has a default (Python)
- [ ] `-h`/`--help` works and matches the usage comment/docstring exactly (single
      source of truth, not a duplicated description)
- [ ] Shebang is `#!/usr/bin/env bash` or `#!/usr/bin/env python3`
- [ ] No bash 4+ features (`declare -A`, `mapfile`, `${var,,}`, `printf -v`)
- [ ] No BSD-vs-GNU-specific `sed -i`/`date` invocations without a fallback
- [ ] All diagnostic/error output goes to stderr; only real results to stdout
- [ ] Lives under the skill's `scripts/` directory, documented in a `## Bundled
      scripts` table in that skill's `SKILL.md`
- [ ] If it wraps an interactive subprocess (`docker compose exec`, etc.) while also
      reading its own stdin, redirect the wrapped process's stdin from `/dev/null`
- [ ] Prefer stdlib-only Python if the script's value proposition includes "no repo
      checkout or dependencies needed"
- [ ] Tested for real — run it, don't just read it (see `tapestry-standalone-viewer`'s
      own history: a `curl`-and-static-file check missed a real client-side bug that
      only a genuine browser run caught)

---

## 6. Keeping This Current

This repo has six scripts as of this writing — small enough that an ad-hoc check during
review covers it without any process overhead:

```bash
git diff --name-only main | grep -E '\.(sh|py)$' | while read -r f; do
  echo "=== $f ==="
  head -20 "$f"
done
```

Run that against the §5 checklist for any new or modified script before merging. A
pre-commit hook or CI workflow (as Wikipedia-AI-Skills' own guidelines set up) is more
machinery than six scripts justify right now — revisit if this repo's script count
grows substantially, but don't build that infrastructure preemptively.
