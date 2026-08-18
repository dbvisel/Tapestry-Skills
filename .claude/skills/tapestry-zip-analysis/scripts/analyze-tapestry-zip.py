#!/usr/bin/env python3
"""Analyze a Tapestry export .zip and print a structured, human-readable report.

Usage:
    analyze-tapestry-zip.py path/to/tapestry.zip [--json]

This mirrors (a subset of) what the real app's importer
(server/src/services/tapestry-import-service.ts) checks, WITHOUT needing the
tapestry-project repo, a running server, or any dependency beyond the Python
stdlib. It is deliberately more lenient than the real importer in some ways
(it doesn't run full Zod-equivalent validation of every field) but flags the
specific failure modes documented in tapestry-zip-authoring's SKILL.md:

  - root.json missing or not valid JSON
  - a version number this script doesn't recognize (0-7 as of last_verified)
  - any `file:/...`-prefixed reference (thumbnail, item source, thumbnail
    rendition source) that doesn't resolve to an actual entry in the zip
  - a media item's `source` entry whose zip filename has no parenthesized
    segment — this doesn't fail root.json's schema validation, but it DOES
    crash the real importer with an uncaught TypeError (see SKILL.md)

See tapestry-zip-authoring's SKILL.md for the full field reference this report
is built from.
"""

import argparse
import json
import re
import sys
import zipfile
from collections import Counter

FILE_PREFIX = "file:/"
ROOT_FILE = "root.json"
KNOWN_VERSIONS = range(0, 8)
MEDIA_ITEM_TYPES = {"audio", "book", "image", "pdf", "video", "webpage"}
PAREN_RE = re.compile(r".*\((.*)\)")


def bundled_path(value):
    if isinstance(value, str) and value.startswith(FILE_PREFIX):
        return value[len(FILE_PREFIX):]
    return None


def check_reference(label, value, entry_names, problems, require_parens=False):
    path = bundled_path(value)
    if path is None:
        return  # external URL or absent — nothing to check
    if path not in entry_names:
        problems.append(f"{label}: references {value!r} but no zip entry named {path!r} exists")
        return
    if require_parens and not PAREN_RE.match(path):
        problems.append(
            f"{label}: zip entry {path!r} has no parenthesized segment — "
            f"the real importer's filename-extraction regex will throw an uncaught "
            f"TypeError on this exact entry (see tapestry-zip-authoring's SKILL.md)"
        )


def walk_presentation(steps):
    """Presentation steps form a backward-linked list via prevStepId.
    Returns the ordered list of steps from first to last, or None if the
    chain is broken (cycles, multiple roots, dangling prevStepId)."""
    if not steps:
        return []
    by_id = {s["id"]: s for s in steps}
    by_prev = {}
    roots = []
    for s in steps:
        prev = s.get("prevStepId")
        if prev is None:
            roots.append(s)
        else:
            if prev in by_prev:
                return None  # two steps claim the same predecessor — broken chain
            by_prev[prev] = s
    if len(roots) != 1:
        return None
    ordered = [roots[0]]
    while ordered[-1]["id"] in by_prev:
        ordered.append(by_prev[ordered[-1]["id"]])
    if len(ordered) != len(steps):
        return None
    return ordered


def describe_step(step):
    if step["type"] == "group":
        return f"group:{step['groupId']}"
    return f"item:{step['itemId']}"


def analyze(zip_path):
    report = {"problems": []}
    problems = report["problems"]

    with zipfile.ZipFile(zip_path) as zf:
        entry_names = set(zf.namelist())
        report["zip_entry_count"] = len(entry_names)
        report["zip_uncompressed_bytes"] = sum(i.file_size for i in zf.infolist())

        if ROOT_FILE not in entry_names:
            problems.append(f"no {ROOT_FILE!r} entry at the zip root — not a valid Tapestry export")
            return report

        try:
            root = json.loads(zf.read(ROOT_FILE))
        except json.JSONDecodeError as e:
            problems.append(f"{ROOT_FILE} is not valid JSON: {e}")
            return report

        version = root.get("version")
        report["version"] = version
        if version not in KNOWN_VERSIONS:
            problems.append(
                f"unrecognized version {version!r} — the real importer would reject this "
                f"with ImportError('unrecognized-version') unless it happens to match a "
                f"newer schema this script doesn't know about yet"
            )
        elif version != max(KNOWN_VERSIONS):
            report["note"] = (
                f"version {version} is not the current schema ({max(KNOWN_VERSIONS)}), but "
                f"that's normal — real-world exports are frequently older versions, and the "
                f"app auto-upgrades them on import via a migration chain. Not a defect."
            )

        report["title"] = root.get("title")
        report["description"] = root.get("description")
        report["id"] = root.get("id")
        report["createdAt"] = root.get("createdAt")
        report["updatedAt"] = root.get("updatedAt")
        report["background"] = root.get("background")
        report["theme"] = root.get("theme")

        items = root.get("items") or []
        report["item_count"] = len(items)
        report["item_types"] = dict(Counter(i.get("type") for i in items))
        webpage_types = [i.get("webpageType") for i in items if i.get("type") == "webpage"]
        if webpage_types:
            report["webpage_types"] = dict(Counter(t or "(generic)" for t in webpage_types))

        report["group_count"] = len(root.get("groups") or [])
        report["rel_count"] = len(root.get("rels") or [])

        presentation = root.get("presentation") or []
        report["presentation_step_count"] = len(presentation)
        if presentation:
            ordered = walk_presentation(presentation)
            if ordered is None:
                problems.append(
                    "presentation steps don't form a single well-formed chain "
                    "(via prevStepId) — check for cycles or multiple/zero roots"
                )
            else:
                report["presentation_order"] = [describe_step(s) for s in ordered]

        check_reference("thumbnail", root.get("thumbnail"), entry_names, problems)

        bundled_media = 0
        external_media = 0
        for item in items:
            item_id = item.get("id", "?")
            if item.get("type") in MEDIA_ITEM_TYPES:
                source = item.get("source")
                check_reference(
                    f"item {item_id} source", source, entry_names, problems, require_parens=True
                )
                if bundled_path(source) is not None:
                    bundled_media += 1
                elif source:
                    external_media += 1
            thumbnail = item.get("thumbnail") or {}
            for rendition in thumbnail.get("renditions") or []:
                check_reference(
                    f"item {item_id} thumbnail rendition",
                    rendition.get("source"),
                    entry_names,
                    problems,
                )
        report["bundled_media_items"] = bundled_media
        report["external_media_items"] = external_media

        group_ids = {g["id"] for g in (root.get("groups") or [])}
        for item in items:
            group_id = item.get("groupId")
            if group_id and group_id not in group_ids:
                problems.append(f"item {item.get('id')} has groupId {group_id!r} not in groups[]")

    return report


def print_report(report):
    if "problems" in report and len(report) == 1:
        print("INVALID:")
        for p in report["problems"]:
            print(f"  - {p}")
        return

    print(f"version:      {report.get('version')}")
    if report.get("note"):
        print(f"  note: {report['note']}")
    print(f"title:        {report.get('title')!r}")
    if report.get("description"):
        print(f"description:  {report['description']!r}")
    print(f"id:           {report.get('id')}")
    print(f"created/updated: {report.get('createdAt')} / {report.get('updatedAt')}")
    print(f"theme/background: {report.get('theme')} / {report.get('background')}")
    print()
    print(f"items ({report.get('item_count', 0)}):")
    for item_type, count in sorted((report.get("item_types") or {}).items(), key=lambda kv: -kv[1]):
        print(f"  {item_type}: {count}")
    if report.get("webpage_types"):
        print("  webpage subtypes:")
        for t, count in sorted(report["webpage_types"].items(), key=lambda kv: -kv[1]):
            print(f"    {t}: {count}")
    print(f"  bundled media (in-zip): {report.get('bundled_media_items', 0)}")
    print(f"  external media (URLs): {report.get('external_media_items', 0)}")
    print()
    print(f"groups: {report.get('group_count', 0)}   rels: {report.get('rel_count', 0)}")
    print(f"presentation steps: {report.get('presentation_step_count', 0)}")
    if report.get("presentation_order"):
        print("  order: " + " -> ".join(report["presentation_order"]))
    print()
    print(f"zip entries: {report.get('zip_entry_count')}   uncompressed size: {report.get('zip_uncompressed_bytes'):,} bytes")

    problems = report.get("problems") or []
    if problems:
        print()
        print(f"PROBLEMS ({len(problems)}):")
        for p in problems:
            print(f"  - {p}")
    else:
        print()
        print("No problems found.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip_path")
    parser.add_argument("--json", action="store_true", help="print the raw report as JSON instead")
    args = parser.parse_args()

    report = analyze(args.zip_path)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)

    sys.exit(1 if report.get("problems") else 0)


if __name__ == "__main__":
    main()
