#!/usr/bin/env python3
"""Extract the release-notes section for a version from CHANGELOG.md.

Usage:
    extract_release_notes.py CHANGELOG.md 0.1.0

Prints the markdown body under the `## [0.1.0]` heading (up to the next
`## ` heading or end of file). Exits non-zero when the section is missing
or empty, so the release workflow fails instead of publishing blank notes.
"""

import re
import sys


def extract(changelog: str, version: str) -> str:
    heading = re.compile(rf"^##\s*\[{re.escape(version)}\][^\n]*\n", re.MULTILINE)
    match = heading.search(changelog)
    if match is None:
        raise ValueError(f"No '## [{version}]' section in CHANGELOG.md")
    rest = changelog[match.end():]
    next_heading = re.search(r"^##\s", rest, re.MULTILINE)
    body = rest[: next_heading.start()] if next_heading else rest
    body = body.strip()
    if not body:
        raise ValueError(f"'## [{version}]' section is empty")
    return body + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} CHANGELOG.md VERSION", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            changelog = f.read()
        sys.stdout.write(extract(changelog, argv[2]))
    except (OSError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
