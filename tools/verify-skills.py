#!/usr/bin/env python3
"""verify-skills.py — Structural self-check for every skill in .claude/skills/.

Tier 1 of this repo's audit maturity model (see CLAUDE.md): cheap, offline,
stdlib-only checks that catch the exact class of drift this repo has hit by
hand — a missing README row, a stale cross-reference after a file move, a
skill whose bundled files nobody documented. Nothing here touches the
network or needs a tapestry-project checkout; it only looks at this repo's
own SKILL.md files and directory structure.

Checks:
  - every .claude/skills/<name>/ has a SKILL.md
  - frontmatter exists and has all required fields, non-empty
  - name matches the directory name
  - license == "MIT", compatibility == "claude-code" (this repo's convention)
  - last_verified is a valid ISO date, not in the future, not older than
    --max-age-days (default 365)
  - every depends_on entry names a skill that actually exists
  - every scripts/, references/, assets/ file is mentioned somewhere in the
    skill's SKILL.md text (an unmentioned bundled file is probably orphaned)
  - every `scripts/...`/`references/...`/`assets/...` path referenced in a
    SKILL.md's bundled-files table actually exists on disk

Usage:
    python3 tools/verify-skills.py
    python3 tools/verify-skills.py --max-age-days 270
    python3 tools/verify-skills.py --skill tapestry-zip-authoring

Exit codes: 0 = clean, 1 = violations found.
"""

import argparse
import re
import sys
from datetime import date, datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_SKILLS_DIR = REPO_ROOT / ".claude" / "skills"

REQUIRED_FIELDS = [
    "name",
    "description",
    "license",
    "compatibility",
    "depends_on",
    "skill_discovery_hints",
    "last_verified",
]
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
BUNDLE_DIRS = ("scripts", "references", "assets")
TABLE_REF_RE = re.compile(r"\|\s*`((?:scripts|references|assets)/[^`]+)`\s*\|")


def read_frontmatter(text: str) -> dict:
    """Best-effort parse of the top-level (non-indented) frontmatter keys.

    Deliberately not a full YAML parser (no new dependency) — this repo's
    frontmatter is simple `key: value` lines, plus one multi-line list
    (`skill_discovery_hints`) whose nested `- keywords: [...]` lines are
    indented. For that one key, the value is the concatenated indented block
    (non-empty if there's at least one nested line) rather than whatever
    (nothing) follows the colon on its own line."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    current_list_key = None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith((" ", "\t")):
            if current_list_key:
                fm[current_list_key] = fm.get(current_list_key, "") + " " + line.strip()
            continue
        current_list_key = None
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not value:
            current_list_key = key  # value lives on following indented lines
        fm[key] = value
    return fm


def parse_depends_on(raw: str) -> list[str]:
    """`depends_on: []` or `depends_on: ["a", "b"]` -> ["a", "b"]."""
    return [a or b for a, b in re.findall(r'"([^"]+)"|\'([^\']+)\'', raw)]


def check_skill(skill_dir: Path, all_skill_names: set[str], max_age_days: int) -> list[str]:
    problems = []
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return [f"{skill_dir.name}: no SKILL.md"]

    text = skill_md.read_text(encoding="utf-8")
    fm = read_frontmatter(text)
    if not fm:
        return [f"{skill_dir.name}: SKILL.md has no frontmatter (must start with '---')"]

    for field in REQUIRED_FIELDS:
        if field not in fm:
            problems.append(f"{skill_dir.name}: frontmatter missing '{field}'")
        elif not fm[field].strip():
            problems.append(f"{skill_dir.name}: frontmatter '{field}' is empty")

    if fm.get("name") and fm["name"] != skill_dir.name:
        problems.append(
            f"{skill_dir.name}: frontmatter name '{fm['name']}' doesn't match directory"
        )
    if fm.get("license") and fm["license"] != "MIT":
        problems.append(f"{skill_dir.name}: license is '{fm['license']}', expected 'MIT'")
    if fm.get("compatibility") and fm["compatibility"] != "claude-code":
        problems.append(
            f"{skill_dir.name}: compatibility is '{fm['compatibility']}', expected 'claude-code'"
        )

    raw_date = fm.get("last_verified", "")
    if raw_date:
        if not DATE_RE.match(raw_date):
            problems.append(f"{skill_dir.name}: last_verified '{raw_date}' is not an ISO date")
        else:
            try:
                verified = datetime.strptime(raw_date, "%Y-%m-%d").date()
                if verified > date.today():
                    problems.append(f"{skill_dir.name}: last_verified '{raw_date}' is in the future")
                elif (date.today() - verified).days > max_age_days:
                    age = (date.today() - verified).days
                    problems.append(
                        f"{skill_dir.name}: last_verified is {age} days old (>{max_age_days}) "
                        f"— re-verify and bump the date"
                    )
            except ValueError:
                problems.append(f"{skill_dir.name}: last_verified '{raw_date}' is not a valid date")

    for dep in parse_depends_on(fm.get("depends_on", "")):
        if dep not in all_skill_names:
            problems.append(f"{skill_dir.name}: depends_on references missing skill '{dep}'")

    for bundle_dir_name in BUNDLE_DIRS:
        bundle_dir = skill_dir / bundle_dir_name
        if not bundle_dir.is_dir():
            continue
        for f in sorted(bundle_dir.iterdir()):
            if f.is_file() and f.name not in text:
                problems.append(
                    f"{skill_dir.name}: {bundle_dir_name}/{f.name} exists but isn't "
                    f"mentioned anywhere in SKILL.md — orphaned?"
                )

    for m in TABLE_REF_RE.finditer(text):
        rel_path = m.group(1)
        if not (skill_dir / rel_path).exists():
            problems.append(f"{skill_dir.name}: SKILL.md references '{rel_path}' but it doesn't exist")

    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--skills-dir", type=Path, default=DEFAULT_SKILLS_DIR)
    ap.add_argument("--skill", action="append", help="only check this skill (repeatable)")
    ap.add_argument("--max-age-days", type=int, default=365)
    args = ap.parse_args(argv)

    if not args.skills_dir.is_dir():
        print(f"error: skills directory not found: {args.skills_dir}", file=sys.stderr)
        return 1

    all_skill_dirs = sorted(d for d in args.skills_dir.iterdir() if d.is_dir())
    all_skill_names = {d.name for d in all_skill_dirs}

    targets = all_skill_dirs
    if args.skill:
        wanted = set(args.skill)
        targets = [d for d in all_skill_dirs if d.name in wanted]
        missing = wanted - {d.name for d in targets}
        for name in missing:
            print(f"  x {name}: no such skill directory")

    violations = []
    for skill_dir in targets:
        violations.extend(check_skill(skill_dir, all_skill_names, args.max_age_days))

    for v in violations:
        print(f"  x {v}")
    print(f"\n{len(targets)} skill(s) checked, {len(violations)} violation(s).")

    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
