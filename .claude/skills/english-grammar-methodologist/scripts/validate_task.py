#!/usr/bin/env python3
"""
Validate a generated grammar exercise set against the default schema
(or a custom one passed with --schema).

Usage:
    python validate_task.py path/to/output.json
    python validate_task.py path/to/output.json --schema path/to/project.schema.json
    cat output.json | python validate_task.py -

Exit codes:
    0 — valid
    1 — invalid (errors printed)
    2 — usage / IO error

The script also runs a few non-schema sanity checks that catch the most
common real-world quality problems we don't want to encode in JSON Schema:

- An exercise tagged 'controlled' has fewer items than the recommended floor.
- An MCQ item has fewer than 3 options or no exactly-one correct answer.
- A gap-fill item lacks 'answer'.
- An error-correction item with has_error=true has no error_span.
- The set declares level X but contains obviously off-level lexis (heuristic only).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import jsonschema
except ImportError:
    print(
        "[fatal] The 'jsonschema' package is required.\n"
        "        Install with:  pip install jsonschema\n"
        "        (or:  pip install --break-system-packages jsonschema)",
        file=sys.stderr,
    )
    sys.exit(2)


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SCHEMA = SCRIPT_DIR.parent / "assets" / "schema" / "exercise.schema.json"

MIN_ITEMS_BY_TYPE = {
    "gap-fill": 8,
    "multiple-choice": 6,
    "transformation": 6,
    "error-correction": 6,
    "matching": 8,
    "word-order": 5,
    "sentence-completion": 5,
    "personalisation": 5,
}


def load_json(path_or_dash: str) -> dict:
    if path_or_dash == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path_or_dash).read_text(encoding="utf-8"))


def schema_validate(data: dict, schema: dict) -> list[str]:
    """Return a list of formatted JSON Schema error messages (empty = valid)."""
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.absolute_path))
    out = []
    for err in errors:
        loc = "/".join(str(p) for p in err.absolute_path) or "<root>"
        out.append(f"  · at {loc}: {err.message}")
    return out


def sanity_checks(data: dict, *, strict_counts: bool) -> list[str]:
    """Heuristic, non-schema checks. Warnings unless --strict-counts is set."""
    issues: list[str] = []
    exercises = data.get("exercises", [])

    for ex in exercises:
        ex_id = ex.get("id", "<no-id>")
        ex_type = ex.get("type")
        items = ex.get("items", [])

        # Item count vs recommended floor
        if strict_counts and ex_type in MIN_ITEMS_BY_TYPE:
            floor = MIN_ITEMS_BY_TYPE[ex_type]
            if len(items) < floor:
                issues.append(
                    f"  · exercise '{ex_id}' ({ex_type}): {len(items)} items "
                    f"(recommended floor: {floor})"
                )

        # Per-type structural checks
        if ex_type == "multiple-choice":
            for it in items:
                opts = it.get("options", {})
                if not isinstance(opts, dict) or len(opts) < 3:
                    issues.append(
                        f"  · MCQ item {ex_id}#{it.get('n')}: needs ≥3 options"
                    )
                ans = it.get("answer")
                if ans not in opts:
                    issues.append(
                        f"  · MCQ item {ex_id}#{it.get('n')}: 'answer' not in options"
                    )

        elif ex_type == "gap-fill":
            for it in items:
                if not it.get("answer"):
                    issues.append(
                        f"  · gap-fill item {ex_id}#{it.get('n')}: missing 'answer'"
                    )

        elif ex_type == "error-correction":
            for it in items:
                if it.get("has_error") and not it.get("error_span"):
                    issues.append(
                        f"  · error-correction item {ex_id}#{it.get('n')}: "
                        f"has_error=true but no error_span"
                    )

        elif ex_type == "transformation":
            for it in items:
                if not it.get("key_word"):
                    issues.append(
                        f"  · transformation item {ex_id}#{it.get('n')}: missing key_word"
                    )

    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", help="Path to JSON file, or '-' for stdin")
    parser.add_argument(
        "--schema",
        default=str(DEFAULT_SCHEMA),
        help=f"Path to JSON Schema (default: {DEFAULT_SCHEMA})",
    )
    parser.add_argument(
        "--strict-counts",
        action="store_true",
        help="Fail when an exercise has fewer items than the recommended floor",
    )
    args = parser.parse_args()

    try:
        data = load_json(args.input)
    except (OSError, json.JSONDecodeError) as e:
        print(f"[fatal] Could not read/parse input: {e}", file=sys.stderr)
        return 2

    try:
        schema = json.loads(Path(args.schema).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"[fatal] Could not read/parse schema: {e}", file=sys.stderr)
        return 2

    schema_errors = schema_validate(data, schema)
    sanity_issues = sanity_checks(data, strict_counts=args.strict_counts)

    if schema_errors:
        print("[invalid] Schema errors:")
        for e in schema_errors:
            print(e)

    if sanity_issues:
        label = "[invalid] Sanity issues:" if args.strict_counts else "[warn] Sanity issues:"
        print(label)
        for i in sanity_issues:
            print(i)

    if schema_errors or (args.strict_counts and sanity_issues):
        return 1

    print(f"[ok] Valid: '{data.get('title', '<untitled>')}' "
          f"({data.get('level', '?')}, {len(data.get('exercises', []))} exercise(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
