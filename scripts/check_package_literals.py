#!/usr/bin/env python3
"""Finds user-facing string literals in a Swift package that aren't resolved
through that package's own String Catalog.

A `Text("…")` / `Button("…")` / `Label("…")` / `.navigationTitle("…")` call is
considered localized only when it passes `bundle: .module` AND its literal is
a key in the package's `Localizable.xcstrings`. Anything else is reported:

  - no `bundle: .module` in the call: SwiftUI resolves it against the app
    bundle, so the package's catalog is never consulted.
  - `bundle: .module` but the key is missing from the package's catalog: the
    string silently renders in English. This is the gap the grep-only check
    missed (the key lived in a sibling module's catalog).

Unlike a line-based grep, this scans whole files, so a literal on the line
after `Text(` (multi-line call) is still seen.

Usage: check_package_literals.py <Sources dir> [path/to/Localizable.xcstrings]
Prints one `path:line: reason: literal` per offending call. No catalog argument
(or a missing file) means every call with a literal is checked against an
empty key set.
"""
import json
import os
import re
import sys

CALL_RE = re.compile(r'(?:\b(?:Text|Button|Label)|\.navigationTitle)\(')
BUNDLE_RE = re.compile(r'bundle:\s*\.module')
INTERPOLATION_RE = re.compile(r'\\\([^)]*\)')
# Format specifiers (%@, %lld, %d, %1$@, ...) collapse to one token so an
# Int-interpolated call site matches its catalog key regardless of specifier.
FORMAT_RE = re.compile(r'%(?:\d+\$)?l*[@dfsu]')


def normalize(literal: str) -> str:
    unescaped = literal.replace('\\"', '"')
    return FORMAT_RE.sub("%@", INTERPOLATION_RE.sub("%@", unescaped))


def read_string(text: str, start: int) -> tuple[str, int]:
    """Returns the raw contents of the string literal opening at `start`."""
    end = start + 1
    while end < len(text) and text[end] != '"':
        end += 2 if text[end] == "\\" else 1
    return text[start + 1:end], end + 1


def find_call_close(text: str, open_index: int) -> int:
    """Index of the `)` matching the `(` at `open_index`, skipping strings."""
    depth = 0
    index = open_index
    while index < len(text):
        char = text[index]
        if char == '"':
            _, index = read_string(text, index)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return len(text)


def load_keys(catalog_path: str | None) -> set[str]:
    if not catalog_path or not os.path.exists(catalog_path):
        return set()
    with open(catalog_path, encoding="utf-8") as f:
        strings = json.load(f).get("strings", {})
    return {normalize(key) for key in strings}


def scan_file(path: str, keys: set[str]):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for match in CALL_RE.finditer(text):
        open_index = match.end() - 1
        cursor = match.end()
        while cursor < len(text) and text[cursor].isspace():
            cursor += 1
        if cursor >= len(text) or text[cursor] != '"':
            continue  # not a literal (a variable, `verbatim:`, etc.)
        literal, _ = read_string(text, cursor)
        args = text[open_index:find_call_close(text, open_index)]
        line = text.count("\n", 0, match.start()) + 1
        if not BUNDLE_RE.search(args):
            yield line, "no bundle: .module", literal
        elif normalize(literal) not in keys:
            yield line, "key missing from catalog", literal


def main() -> None:
    sources_dir = sys.argv[1]
    keys = load_keys(sys.argv[2] if len(sys.argv) > 2 else None)
    for dirpath, _, filenames in os.walk(sources_dir):
        for filename in sorted(filenames):
            if not filename.endswith(".swift"):
                continue
            path = os.path.join(dirpath, filename)
            for line, reason, literal in scan_file(path, keys):
                print(f"{path}:{line}: {reason}: {literal}")


if __name__ == "__main__":
    main()
