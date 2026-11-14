#!/usr/bin/env python3
"""ci/check_fmt.py -- the formatting gate.

## What this checks

Every MoonBit source in the repository, formatted by the toolchain's own
formatter (`moon fmt`), compared with the source as it stands on disk. A file
the formatter would rewrite is a failure: the tree is not in the state the
formatter produces, so the next `moon fmt` hands its author a diff that
nobody reviewed.

## Why not `moon fmt --check`

`moon fmt --check` renders its diff by running

    git --no-pager diff --color=always --no-index <source> <formatted>

and `git diff --no-index` exits 1 when the two files differ -- which is
exactly what a file that needs formatting looks like. The toolchain reads
that exit code as "the command failed to run", so the check reports a git
failure instead of a formatting verdict, and hands back 4294967295 rather
than a usable 1. The verdict may still be right; what fails is the reporting
step, and a gate cannot tell the two apart.

So the verdict is computed here instead. The sources are copied to a scratch
directory, `moon fmt` is run there in write mode -- no diff, no git, and the
repository is never written to -- and the formatted copy is compared with the
original byte for byte. The answer is the same on every platform, the exit
code is the exit code of this script, and the output names the files.

The scratch project carries the dependency cache across when it is there,
so `moon fmt` there resolves its imports without reaching the network. It
does not need it: `moon fmt` formats the sources without resolving the
dependency graph, which is why this check runs offline on a fresh clone.

## What it does not do

It does not reformat the repository. Formatting is the author's move: this
gate says which files drift, and the author decides when to run `moon fmt`.
"""

import io
import os
import shutil
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover - very old interpreters
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The suffixes the formatter can own: MoonBit sources and the package
# manifests. `.mbti` files are generated interfaces and the formatter does
# not rewrite them; they are copied and compared anyway, so a formatter that
# starts rewriting them is visible here instead of silent.
SOURCE_SUFFIXES = (".mbt", ".mbti", ".pkg")

# Directories that hold no sources: build output, the dependency cache, git.
SKIP_DIRS = ("_build", ".mooncakes", ".git", "node_modules")

# The files the scratch project needs beside the sources, so that `moon fmt`
# there sees the project it sees here. `moon.mod` is the manifest, and it
# names `README.md`.
PROJECT_FILES = ("moon.mod", "README.md")

# The dependency cache, copied so the scratch project resolves its imports
# offline.
DEP_CACHE = ".mooncakes"


def source_files(root):
    """Every candidate source file, as a '/'-separated path relative to root."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in filenames:
            if name.endswith(SOURCE_SUFFIXES):
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                out.append(rel.replace(os.sep, "/"))
    return sorted(out)


def copy_project(root, dest, files):
    """Copy the sources and the project files into the scratch directory."""
    for rel in files:
        here = os.path.join(root, rel.replace("/", os.sep))
        there = os.path.join(dest, rel.replace("/", os.sep))
        parent = os.path.dirname(there)
        if parent and not os.path.isdir(parent):
            os.makedirs(parent)
        shutil.copy2(here, there)
    for name in PROJECT_FILES:
        source = os.path.join(root, name)
        if os.path.isfile(source):
            shutil.copy2(source, os.path.join(dest, name))
    cache = os.path.join(root, DEP_CACHE)
    if os.path.isdir(cache):
        try:
            shutil.copytree(cache, os.path.join(dest, DEP_CACHE))
        except OSError:
            # `moon fmt` does not resolve the dependency graph, so a cache it
            # could not copy is not a failure: the check stays offline either
            # way, and a cache another process holds open is not our business.
            pass


def run_fmt(dest):
    """Run `moon fmt` in the scratch project. Returns (exit_code, output)."""
    try:
        proc = subprocess.run(["moon", "fmt"], cwd=dest,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError:
        return 127, "moon is not on PATH"
    return proc.returncode, (proc.stdout or b"").decode("utf-8", "replace")


def read_bytes(path):
    with io.open(path, "rb") as fh:
        return fh.read()


def main():
    files = source_files(ROOT)
    if not files:
        print("[FAIL] no MoonBit sources found under %s" % ROOT)
        print("       a gate that checks nothing is not a gate")
        return 1

    scratch = tempfile.mkdtemp(prefix="moonbit_markdown-fmt-")
    try:
        copy_project(ROOT, scratch, files)
        code, out = run_fmt(scratch)
        if code != 0:
            print("[FAIL] `moon fmt` failed on the scratch copy (exit %d)" % code)
            for line in out.splitlines()[-14:]:
                print("       %s" % line)
            return 2
        drifted = []
        for rel in files:
            original = os.path.join(ROOT, rel.replace("/", os.sep))
            formatted = os.path.join(scratch, rel.replace("/", os.sep))
            if not os.path.isfile(formatted):
                drifted.append(rel)
                continue
            if read_bytes(original) != read_bytes(formatted):
                drifted.append(rel)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if drifted:
        print("[FAIL] %d of %d files are not formatted:" % (len(drifted), len(files)))
        for rel in drifted:
            print("       %s" % rel)
        print("       run `moon fmt` and commit the result")
        return 1

    print("[PASS] all %d files are formatted" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
