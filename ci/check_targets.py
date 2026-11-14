#!/usr/bin/env python3
"""ci/check_targets.py -- the four-target verification.

## What this checks

That the module really builds, starts and passes its tests on all four
targets the toolchain offers: native, js, wasm and wasm-gc. For each target
it builds the executable from scratch, insists that the artefact is there,
runs it, and runs the test suite.

## Why the artefact has to be looked for

`moon build` exiting 0 says that the build did not fail. It does not say
that a program came out of it: a target the toolchain does not support is
dropped with a warning, and the command still exits 0. The four targets
here are all supported, so that is the shape of the risk rather than the
reason for the check -- but "the build did not fail" and "there is a
program to run" are two different claims, and only the second one is what
the module promises.

So the artefact is looked for, and then it is run. A target that produces a
file nothing can start is not a target the module reaches.

## Why a fresh build directory per target

A build tree that is already up to date prints "no work to do" and exits 0.
That is the toolchain being right -- there was nothing to do -- but it is
also what a check would see if the target were not built at all. So each
target is built in its own directory, which is emptied first: the build in
this check is always a build from scratch.

## The targets, and what each of them can do

All four carry the whole module: the pure packages, the command line tool,
and the executable in the root. What differs is the file and process layer
underneath them, and one thing the wasm-gc host cannot do at all: start
another program. The commands that drive a browser therefore report that
there, rather than producing a page.
"""

import glob
import os
import re
import shutil
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover - very old interpreters
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The build tree this check owns. It is inside `_build`, which the repository
# ignores, and it is emptied before every target so that each build is a
# build from scratch.
BUILD_ROOT = os.path.join(ROOT, "_build", "targets")

# The name of the executable the root package produces.
EXECUTABLE = "moonbit_markdown"

# The four targets, and how each of them is run.
#
#   native   the executable itself
#   js       node, which is what the js backend emits for
#   wasm     moonrun, the host that starts a wasm module
#   wasm-gc  moonrun, the host that starts a wasm-gc module
TARGETS = [
    ("native", [".exe", ""], []),
    ("js", [".js"], ["node"]),
    ("wasm", [".wasm"], ["moonrun"]),
    ("wasm-gc", [".wasm"], ["moonrun"]),
]

# What the executable prints when it starts with nothing to do. It is the
# name of the tool, so a run that printed nothing is not a run that worked.
BANNER = "riantr/moonbit_markdown"

# The line `moon test` prints: the tests that ran, and the ones that failed.
TEST_LINE_RE = re.compile(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)")

TIMEOUT = 1800


def run(argv, cwd=ROOT):
    """Run one argv. Returns (exit_code, combined_output_text)."""
    try:
        proc = subprocess.run(
            argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=TIMEOUT,
        )
        return proc.returncode, (proc.stdout or b"").decode("utf-8", "replace")
    except FileNotFoundError:
        return 127, "command not found: %s" % argv[0]
    except subprocess.TimeoutExpired as exc:
        out = "timed out after %ss" % TIMEOUT
        if exc.output:
            out += "\n" + exc.output.decode("utf-8", "replace")
        return 124, out


def target_dir(target):
    return os.path.join(BUILD_ROOT, target)


def find_artifact(target, suffixes):
    """The executable the build produced, or None when there is none.

    The suffixes are a preference order, not a set: the native build writes
    `moonbit_markdown.exe` on Windows and `moonbit_markdown` elsewhere, and
    the extension-less name is only the answer when nothing else is there.
    """
    pattern = os.path.join(target_dir(target), target, "*", "build", EXECUTABLE + "*")
    paths = sorted(glob.glob(pattern))
    for suffix in suffixes:
        for path in paths:
            name = os.path.basename(path)
            if not name.endswith(suffix):
                continue
            if suffix == "" and name != EXECUTABLE:
                continue
            return path
    return None


def check_build(target):
    """Build the module for one target from scratch."""
    directory = target_dir(target)
    if os.path.isdir(directory):
        shutil.rmtree(directory, ignore_errors=True)
    code, out = run(["moon", "build", "--target", target,
                     "--target-dir", directory])
    if code != 0:
        return False, "the build failed (exit %d)" % code, out
    return True, "built", out


def check_artifact(target, suffixes):
    """The artefact has to be there: a build that produced nothing is not a
    build that worked."""
    path = find_artifact(target, suffixes)
    if path is None:
        return False, "no %s was produced" % EXECUTABLE, ""
    return True, os.path.relpath(path, ROOT), ""


def check_runs(target, suffixes, runner):
    """The artefact has to start, and to say what it is."""
    path = find_artifact(target, suffixes)
    if path is None:
        return False, "nothing to run", ""
    code, out = run(list(runner) + [path])
    if code != 0:
        return False, "it exited with %d" % code, out
    if BANNER not in out:
        return False, "it printed no banner", out
    return True, "it starts", ""


def check_tests(target):
    """The test suite has to run on this target, and it has to run some
    tests: a suite that ran none of them proves nothing."""
    directory = target_dir(target)
    code, out = run(["moon", "test", "--target", target,
                     "--target-dir", directory])
    if code != 0:
        return False, "the tests failed (exit %d)" % code, out
    match = None
    for found in TEST_LINE_RE.finditer(out):
        match = found
    if match is None:
        return False, "the tests printed no summary", out
    total, passed, failed = (int(match.group(i)) for i in (1, 2, 3))
    if total <= 0:
        return False, "the tests ran none of them", out
    if failed != 0:
        return False, "%d of %d tests failed" % (failed, total), out
    return True, "%d tests passed" % total, ""


def main():
    failures = []
    green = []

    for target, suffixes, runner in TARGETS:
        steps = []

        ok, detail, out = check_build(target)
        steps.append(("build", ok, detail, out))
        if ok:
            ok, detail, out = check_artifact(target, suffixes)
            steps.append(("artefact", ok, detail, out))
        if ok:
            ok, detail, out = check_runs(target, suffixes, runner)
            steps.append(("run", ok, detail, out))
        if ok:
            ok, detail, out = check_tests(target)
            steps.append(("tests", ok, detail, out))

        failed = [s for s in steps if not s[1]]
        if failed:
            name, _, detail, out = failed[0]
            failures.append((target, "%s: %s" % (name, detail), out))
            print("  [FAIL] %-8s %s: %s" % (target, name, detail))
            continue

        green.append(target)
        print("  [PASS] %-8s %s" % (target, ", ".join(s[2] for s in steps)))

    print("")
    if failures:
        for target, detail, out in failures:
            print("[FAIL] %s: %s" % (target, detail))
            for line in out.splitlines()[-12:]:
                print("       %s" % line)
        print("targets: %d/%d" % (len(green), len(TARGETS)))
        return 1

    print("[PASS] all %d targets build, start and pass their tests: %s"
          % (len(TARGETS), ", ".join(green)))
    print("targets: %d/%d" % (len(green), len(TARGETS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
