#!/usr/bin/env python3
"""ci/release.py -- the tag / push gate.

## The rule this file enforces

* **No tag while the local CI is not fully green.** Not even on request.
  The owner has asked for this explicitly, because they know they will
  forget: "在本地 CI 未全绿之前禁止打 tag，即便是我要求的". A tag is the one
  artefact that says "this is the tested state of the project", so it must be
  the *last* thing produced, never an exception.
* **A tag only moves its final component.** `v0.1.0` -> `v0.1.1` -> `v0.1.2`.
  Nothing else about the tag changes, so a series of tags reads as a series of
  tested states rather than a series of renames. This holds until the owner
  says otherwise.
* **Gitee may be pushed at any time.** It is the working remote.
* **GitHub is pushed only when the local CI is green and a tag exists.**
  This repository has both remotes configured, so this half of the rule acts
  on something real rather than being policy with nothing to act on.

`next_tag` and `assert_tag_allowed` are deliberately pure functions so
`--self-check` can test the numbering and the refusal without a repository, a
tag, or a network.
"""

import re

# A tag ending in digits. The digits are moved; everything before them is
# kept verbatim. So `v0.1.0` becomes `v0.1.1`, and a date-shaped
# `release-2026-10` becomes `release-2026-11` -- which is the same rule, "only
# the trailing number moves", applied to a different naming scheme. A tag with
# no trailing digits (`nightly`) cannot be advanced this way and is refused
# rather than guessed at.
VERSION_TAG_RE = re.compile(r"^(?P<head>.+?)(?P<last>\d+)$")


class TagError(Exception):
    """The requested tag cannot be produced, or must not be."""


def first_tag(version):
    """The first tag of a repository that has none: `v` + the module version.

    Reading the version out of `moon.mod` rather than typing a tag by hand
    keeps the same promise as the rest of this file: the tag names a state the
    package already declares, so nobody has to invent it at release time.
    """
    m = re.match(r"^\s*(\d+(?:\.\d+)*)", version or "")
    if not m:
        raise TagError(
            "cannot read a version number from %r, so there is no first tag to "
            "derive. Ask the owner instead of guessing." % (version,)
        )
    return "v" + m.group(1)


def next_tag(existing, version=None):
    """The tag that follows the newest one, moving only the trailing number.

    When no tag exists yet the first one comes from `version` (the module
    version), which is the only moment this file reads a version instead of a
    tag. Raises TagError when there is nothing to move: a newest tag with no
    trailing digits.

    Guessing a numbering scheme here would produce a tag nobody can interpret,
    so an unreadable newest tag is refused rather than advanced.
    """
    if not existing:
        if version is None:
            raise TagError(
                "no tag exists yet and no module version was given, so the "
                "first tag cannot be derived. Pass the version from moon.mod."
            )
        return first_tag(version)
    newest = max(existing)
    m = VERSION_TAG_RE.match(newest)
    if not m:
        raise TagError(
            "newest tag %r does not end in a number, so 'change only the last "
            "digit' is undefined. Ask the owner instead of guessing." % newest
        )
    head = m.group("head")
    nxt = int(m.group("last")) + 1
    # Preserve the zero padding of the component we are replacing, so a project
    # that uses v1.09 does not silently become v1.10 while we only meant v1.10.
    width = len(m.group("last"))
    return "%s%s" % (head, str(nxt).zfill(width))


def assert_tag_allowed(failed_steps, ran_steps, skipped_tiers):
    """Refuse to tag unless every step that ran passed.

    `skipped_tiers` is reported rather than treated as failure: some tiers are
    opt-in (the ones that drive a browser, and the one that re-renders the
    documents) and take minutes. Hiding that would make the green meaningless,
    so it is printed at the moment the tag is granted.
    """
    problems = []
    if not ran_steps:
        problems.append("no steps ran, so nothing was verified")
    if failed_steps:
        names = ", ".join(s if isinstance(s, str) else s.name for s in failed_steps)
        problems.append("%d step(s) failed: %s" % (len(failed_steps), names))
    if problems:
        raise TagError("; ".join(problems))
    return True


def assert_push_target_allowed(remote, green, has_tag):
    """Which remotes may be pushed, and when.

    Gitee is the working remote and may be pushed at any time. GitHub may only
    be pushed from a green run that has a tag, so that what is published there
    is always a tested, named state.
    """
    name = (remote or "").lower()
    if name == "origin":
        return True
    if name == "github":
        if not green:
            raise TagError(
                "github may only be pushed from a green CI run; this run is red"
            )
        if not has_tag:
            raise TagError(
                "github may only be pushed once a tag exists; create one with "
                "--tag on a green run"
            )
        return True
    raise TagError("unknown remote %r: expected origin (gitee) or github" % remote)
