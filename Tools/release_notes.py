# -*- coding: utf-8 -*-
"""Pull ONE version's notes out of CHANGELOG.md into RELEASE_NOTES.md.

The packager ships whatever RELEASE_NOTES.md contains. StatCoach releases its two
flavors on their own schedules - 1.1.17, 1.1.18 and 1.1.19 were TBC only, 1.1.11
and 1.1.13 were retail only - so the notes for a release are the section for that
version AND that flavor, never both.

An empty changelog is also the one thing Wago refuses outright (HTTP 422), and it
does so AFTER CurseForge has already accepted the file, which leaves a version
live on one store and missing on the other. So a missing section is a hard error
here, before anything is uploaded.

    python Tools/release_notes.py 1.1.21 tbc
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(HERE, "CHANGELOG.md")
OUT = os.path.join(HERE, "RELEASE_NOTES.md")

FLAVOR_LABEL = {"tbc": "TBC", "bcc": "TBC", "retail": "Retail", "mainline": "Retail"}


def section(version, label):
    """The text under '# StatCoach <version> (<label>)', up to the next heading."""
    text = io.open(CHANGELOG, encoding="utf-8").read()
    heading = re.compile(
        r"^# StatCoach %s \(%s\)\s*$" % (re.escape(version), re.escape(label)), re.M
    )
    m = heading.search(text)
    if not m:
        return None
    rest = text[m.end():]
    nxt = re.search(r"^# StatCoach ", rest, re.M)
    body = rest[: nxt.start()] if nxt else rest
    # The separator between entries belongs to the file, not to the entry.
    return body.strip().rstrip("-").strip()


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: release_notes.py <version> <tbc|retail>")
    version = sys.argv[1].lstrip("vV")
    flavor = sys.argv[2].lower()
    label = FLAVOR_LABEL.get(flavor)
    if not label:
        sys.exit("unknown flavor %r - expected tbc or retail" % sys.argv[2])

    body = section(version, label)
    if not body:
        sys.exit(
            "CHANGELOG.md has no '# StatCoach %s (%s)' section.\n"
            "Write the notes for this release before publishing - Wago rejects an\n"
            "empty changelog, and it does so after CurseForge has taken the file."
            % (version, label)
        )

    io.open(OUT, "w", encoding="utf-8", newline="\n").write(
        "# StatCoach %s (%s)\n\n%s\n" % (version, label, body)
    )
    print("RELEASE_NOTES.md written for %s (%s), %d characters."
          % (version, label, len(body)))


if __name__ == "__main__":
    main()
