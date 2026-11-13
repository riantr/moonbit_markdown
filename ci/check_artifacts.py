#!/usr/bin/env python3
"""ci/check_artifacts.py -- the pinned-hash gate.

## What this checks, and why it reads README.md

The generated documents in the repository root are build products, and two of
them are byte-stable: the same source and the same code produce the same bytes.
README.md states their SHA256, so a reader can tell a real build from a
hand-edited page.

Checking a hash against a constant kept in a second file would let the constant
and the document drift apart -- the README would keep promising one value while
CI enforced another, and the README is the one a human reads. So this script
parses the table out of README.md and enforces exactly what that table says. If
the wording of the table changes so that a row can no longer be read, the gate
goes red rather than quietly checking nothing.

## What it does not do

It does not regenerate the documents. Regenerating needs the browser settings
this machine was configured with, and a gate that only passes on the machine it
was written on is not a gate. Regeneration is a separate, documented command;
this gate answers the narrower question "is the tree in the state README.md
names", which is the question a tag asks.
"""

import hashlib
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, "README.md")

# | `name.ext` | `HEX` |  -- the shape of a pinned row in README.md.
ROW_RE = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*`([0-9A-Fa-f]{64})`\s*\|\s*$", re.M)

# Only rows under the heading that introduces the table are pins; the same
# table shape elsewhere in the README (a plan, an example) must not be read as
# a promise.
ANCHOR_RE = re.compile(r"^## The documents in the root are generated\s*$", re.M)


def pinned_rows(text):
    """Every (file name, hash) pair the README pins, in document order."""
    anchor = ANCHOR_RE.search(text)
    if not anchor:
        raise ValueError(
            "README.md no longer has a '## The documents in the root are "
            "generated' section, so the pinned table cannot be located"
        )
    # Stop at the next top-level heading: the table belongs to this section.
    rest = text[anchor.end():]
    nxt = re.search(r"^## ", rest, re.M)
    section = rest if not nxt else rest[:nxt.start()]
    return ROW_RE.findall(section)


def sha256_of(path):
    h = hashlib.sha256()
    with io.open(path, "rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().upper()


def main():
    with io.open(README, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    try:
        rows = pinned_rows(text)
    except ValueError as exc:
        print("[FAIL] %s" % exc)
        return 1

    if not rows:
        print("[FAIL] README.md pins no document, so this gate would verify nothing")
        return 1

    bad = 0
    for name, want in rows:
        path = os.path.join(ROOT, name)
        if not os.path.isfile(path):
            print("[FAIL] %s is missing" % name)
            print("       regenerate it, or delete the row from README.md")
            bad += 1
            continue
        got = sha256_of(path)
        if got != want.upper():
            print("[FAIL] %s" % name)
            print("       README says %s" % want.upper())
            print("       on disk    %s" % got)
            bad += 1
            continue
        print("[PASS] %s  %s" % (name, got))

    print("")
    if bad:
        print("[FAIL] %d of %d pinned documents do not match README.md"
              % (bad, len(rows)))
        return 1
    print("[PASS] all %d pinned documents match README.md" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
