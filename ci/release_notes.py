#!/usr/bin/env python3
"""Print the CHANGELOG.md section for one version, for use as a release body.

    python3 ci/release_notes.py 1.1

A section starts at "## <version>" and runs until the next "## " heading or the
end of the file. If the version has no section, a one-line fallback is printed
and the exit code is 1 — the release workflow ignores that code on purpose, so
a forgotten changelog entry never blocks a release, it just produces a plainer
body.
"""
import os
import re
import sys

CHANGELOG = os.path.join(os.path.dirname(__file__), os.pardir, "CHANGELOG.md")


def extract(text, version):
    """Return the body below '## <version>', or None when it is absent."""
    heading = re.compile(r"^##\s+", re.MULTILINE)
    wanted = None
    marks = list(heading.finditer(text))
    for i, m in enumerate(marks):
        end_of_line = text.find("\n", m.end())
        if end_of_line == -1:
            end_of_line = len(text)
        title = text[m.end():end_of_line].strip()
        # Accept "1.1" as well as "v1.1" and "1.1 - 2026-08-01".
        if title == version or title.lstrip("vV").split()[0:1] == [version]:
            start = end_of_line + 1
            stop = marks[i + 1].start() if i + 1 < len(marks) else len(text)
            wanted = text[start:stop].strip()
            break
    return wanted


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: release_notes.py <version>\n")
        return 2
    version = sys.argv[1]

    try:
        with open(CHANGELOG, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as err:
        sys.stderr.write("cannot read CHANGELOG.md: {}\n".format(err))
        print("Automated release of GzLevelUp {}.".format(version))
        return 1

    section = extract(text, version)
    if not section:
        sys.stderr.write("no CHANGELOG.md section for version {}\n".format(version))
        print("Automated release of GzLevelUp {}.".format(version))
        return 1

    print(section)
    return 0


if __name__ == "__main__":
    sys.exit(main())
