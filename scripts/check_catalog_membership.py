#!/usr/bin/env python3
"""Filters grep matches (one per line, "path:lineno:content") to only those
whose literal string isn't a key in a given Localizable.xcstrings.

Used by audit_hardcoded_strings.sh for the Viku app target, which has no
`bundle: .module` to grep for (Bundle.main is already correct there) — the
only way to tell a real miss from an already-cataloged literal is to check
the catalog itself.

Usage: check_catalog_membership.py <path/to/Localizable.xcstrings>
Reads grep match lines on stdin, writes the ones with no catalog entry.
"""
import json
import re
import sys

LITERAL_RE = re.compile(r'\b(?:Text|Button|Label)\(|\.navigationTitle\(')
STRING_LITERAL_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERPOLATION_RE = re.compile(r'\\\([^)]*\)')


def extract_literal(line: str) -> str | None:
    match = LITERAL_RE.search(line)
    if not match:
        return None
    rest = line[match.end():]
    string_match = STRING_LITERAL_RE.match(rest.lstrip())
    if not string_match:
        return None
    raw = string_match.group(1)
    # Swift's `\"` -> a literal quote; any `\(...)` interpolation becomes a
    # catalog format specifier. Every interpolation in this module today is
    # a String, so this assumes `%@` — revisit if an Int/etc. one is added.
    unescaped = raw.replace('\\"', '"')
    return INTERPOLATION_RE.sub("%@", unescaped)


def main() -> None:
    catalog_path = sys.argv[1]
    with open(catalog_path, encoding="utf-8") as f:
        catalog = json.load(f)
    keys = set(catalog.get("strings", {}).keys())

    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        literal = extract_literal(line)
        if literal is not None and literal in keys:
            continue
        print(line)


if __name__ == "__main__":
    main()
