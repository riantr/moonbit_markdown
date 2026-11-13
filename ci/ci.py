#!/usr/bin/env python3
"""ci/ci.py -- the one CI engine for this repository.

## Why a script and not only a workflow file

A GitHub Actions workflow and a local shell loop are two pieces of code that
drift. The rule this repository has to keep -- "no tag before the local CI is
green" -- is a promise about the *local* run, so the accounting has to live
somewhere a local run can produce it too. `.github/workflows/ci.yml` is a thin
shell that calls this file, so the local and remote runs cannot disagree about
what passed.

## Usage

    python ci/ci.py --list                 # show the steps
    python ci/ci.py                        # env + build + gates
    python ci/ci.py --tiers browser        # the browser checks (slow, needs Chrome)
    python ci/ci.py --tiers spec           # the CommonMark measurement (~2 min)
    python ci/ci.py --only test            # steps whose name contains "test"
    python ci/ci.py --self-check           # verify this engine's own accounting
    python ci/ci.py --check-release        # would a tag be allowed? change nothing
    python ci/ci.py --tiers ... --tag      # create the next tag, only if green
    python ci/ci.py --tiers ... --tag --push   # ... and push, per the policy

## Tiers

    env      tool versions. Cheap, and the first thing to paste into a bug
             report -- "it used to pass" is usually a toolchain delta.
    build    `moon check`, `moon test`, and the four pure packages on all four
             targets.
    gates    the checks that need nothing but this repository: the pinned
             artefact hashes, read out of README.md.
    browser  the checks that drive Chrome: the page, the Markdown page, and the
             PDF comparison. Needs the generated documents to exist.
    spec     the CommonMark measurement, 652 examples. Downloads the spec on
             the first run and takes about two minutes.

The default is env + build + gates: it is portable (no browser, no network)
and it is what the tag is normally granted from. The other two are opt-in
because they are slow, and at tag time they are *named* rather than silently
dropped -- a green that quietly ignored the browser checks is not green.
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import time

# The console on this machine is cp936. A failing step's tail routinely holds
# characters its author chose, and printing them raised UnicodeEncodeError
# *while reporting a failure* -- so the engine died on the step it was meant to
# explain. Decode with "replace" and encode with "replace" too.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover - very old interpreters
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARTIFACT_DIR = os.path.join(ROOT, "ci", "artifacts")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release as rel  # noqa: E402  -- must follow the sys.path insert above

# The four packages that carry no process dependency. `src/mdcli` is native-only
# by construction (it reads files and starts processes), so it is checked on
# native alone.
PURE_PACKAGES = ["src/text", "src/md", "src/mermaid", "src/printpdf"]
TARGETS = ["native", "js", "wasm", "wasm-gc"]

# The source document the root artefacts are generated from. It is tracked by
# git, so a clone can regenerate them.
SOURCE_MMD = "riantr-moonbit_doubleML_0.164.28_0.1.20261012_20261023T005706Z.mmd"

TIERS = ("env", "build", "gates", "browser", "spec")

# The tiers that are opt-in, and therefore have to be named when a tag is
# granted. This is a measurement, not a preference: browser needs Chrome and
# takes minutes, spec downloads the CommonMark spec and takes about two.
OPT_IN_TIERS = ("browser", "spec")

DEFAULT_TIMEOUT = 3600

STATUS_ICON = {"passed": "PASS", "failed": "FAIL", "skipped": "SKIP"}

# A step that exits 0 while printing a FAIL line is a broken step. Believing
# the exit code alone would let that ship silently.
FAIL_LINE_RE = re.compile(r"^\s*(?:\[)?FAIL\b", re.M)

# A tool that exits 0 having run nothing is not a pass: `moon test` on a package
# with no tests does exactly that. The guard is opt-in per step rather than
# global, so it cannot silently change the verdict of steps that were already
# green.
ZERO_WORK_RE = re.compile(r"Total tests:\s*0\b")


class Step(object):
    def __init__(self, tier, name, argv, timeout=DEFAULT_TIMEOUT,
                 zero_work_guard=False, verdict=None):
        self.tier = tier
        self.name = name
        self.argv = argv
        self.timeout = timeout
        self.zero_work_guard = zero_work_guard
        # A callable that reads the step's own output and returns
        # (ok, detail). It exists for the checks whose pass condition is a
        # NUMBER rather than an exit code -- the conformance count is the one
        # example: improving it must not turn CI red, and losing ground must.
        self.verdict = verdict
        self.status = "skipped"
        self.detail = ""
        self.seconds = 0.0
        self.exit_code = None
        self.tail = ""
        self.log = ""

    def as_dict(self):
        d = {
            "tier": self.tier,
            "name": self.name,
            "status": self.status,
            "detail": self.detail,
            "seconds": round(self.seconds, 1),
            "exit_code": self.exit_code,
        }
        if self.log:
            d["full_log"] = "steps/" + self.log
        return d


def _run_argv(argv, cwd, timeout):
    """Run one argv. Returns (exit_code, combined_output_text)."""
    try:
        proc = subprocess.run(
            argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return proc.returncode, (proc.stdout or b"").decode("utf-8", "replace")
    except FileNotFoundError as exc:
        return 127, "command not found: %s (%s)" % (argv[0], exc)
    except subprocess.TimeoutExpired as exc:
        out = "timed out after %ss" % timeout
        if exc.output:
            out += "\n" + exc.output.decode("utf-8", "replace")
        return 124, out


def _safe_log_name(step):
    """A step name is reduced to a conservative file name: Windows rejects
    `\\ : * ? " < > |` in a path component, and the names here carry spaces and
    brackets."""
    keep = []
    for ch in step.name:
        keep.append(ch if (ch.isalnum() or ch in "._-") else "_")
    out = "".join(keep).strip("._") or "step"
    return out[:120] + ".log"


def _keep_full_output(step, out):
    """Persist a failing step's ENTIRE output, not just the tail.

    The tail is what the console gets and it is the right size for a green run.
    It is the wrong size for a red one: the question after a failure is "which
    example, which page", and the answer is usually in the part the tail
    dropped. Steps that pass write nothing -- an artefact full of green noise
    is an artefact nobody opens.
    """
    step.log = _safe_log_name(step)
    directory = os.path.join(ARTIFACT_DIR, "steps")
    try:
        if not os.path.isdir(directory):
            os.makedirs(directory)
        with io.open(os.path.join(directory, step.log), "w",
                     encoding="utf-8", errors="replace") as fh:
            fh.write(out)
    except OSError as exc:
        sys.stderr.write("could not keep full output for %s: %s\n"
                         % (step.name, exc))
        step.log = ""


def run_step(step):
    start = time.time()
    code, out = _run_argv(step.argv, ROOT, step.timeout)
    step.seconds = time.time() - start
    step.exit_code = code

    lines = [ln for ln in out.splitlines() if ln.strip()]
    step.tail = "\n".join(lines[-14:])

    if code != 0:
        step.status = "failed"
        step.detail = "exit %d" % code
        _keep_full_output(step, out)
        return False

    if FAIL_LINE_RE.search(out):
        step.status = "failed"
        step.detail = "exit 0 but the output printed FAIL"
        _keep_full_output(step, out)
        return False

    if step.zero_work_guard and ZERO_WORK_RE.search(out):
        step.status = "failed"
        step.detail = "vacuous pass: ran 0 tests"
        _keep_full_output(step, out)
        return False

    if step.verdict is not None:
        ok, detail = step.verdict(out)
        step.detail = detail
        if not ok:
            step.status = "failed"
            _keep_full_output(step, out)
            return False
        step.status = "passed"
        return True

    step.detail = "ok"
    step.status = "passed"
    return True


# --------------------------------------------------------------------------
# the steps
# --------------------------------------------------------------------------

def env_steps():
    return [
        Step("env", "moon version", ["moon", "version", "--all"], timeout=300),
        Step("env", "node version", ["node", "--version"], timeout=120),
        Step("env", "python version", ["python", "--version"], timeout=120),
    ]


def build_steps():
    steps = [
        Step("build", "moon check", ["moon", "check"]),
        # `moon test` exits 0 while running nothing on a package with no tests;
        # the guard is on because 0 tests is not this repository's state.
        Step("build", "moon test", ["moon", "test"], zero_work_guard=True),
        Step("build", "pure packages on all targets",
             ["moon", "check", "--target", "all"] + PURE_PACKAGES),
    ]
    return steps


def conformance_verdict(out):
    """The CommonMark count: pass when it does not fall below the floor.

    The floor is what the repository claims in README.md, so the claim and the
    measurement cannot drift apart. Improving the parser must not turn CI red,
    which is why this is a floor and not an equality.
    """
    m = None
    for m2 in re.finditer(r"conformance:\s*(\d+)/(\d+)", out):
        m = m2
    if m is None:
        return False, "no conformance line in the output"
    got, total = int(m.group(1)), int(m.group(2))
    floor = conformance_floor()
    if total != 652:
        return False, "expected 652 examples, the spec gave %d" % total
    if got < floor:
        return False, "%d/%d is below the pinned floor of %d" % (got, total, floor)
    return True, "%d/%d (floor %d)" % (got, total, floor)


def conformance_floor():
    """The count README.md promises, read out of README.md."""
    text = read_text("README.md")
    m = re.search(r"\*\*(\d+) of the (\d+) examples agree", text)
    if not m:
        raise ValueError(
            "README.md no longer states the conformance in the form "
            "'**N of the M examples agree', so the floor cannot be read"
        )
    return int(m.group(1))


def gate_steps():
    return [
        Step("gates", "pinned artefact hashes",
             ["python", os.path.join("ci", "check_artifacts.py")]),
    ]


def browser_steps():
    return [
        Step("browser", "verify_page.js",
             ["node", "verify_page.js", "moonbit_doubleML_state_diagram.html",
              SOURCE_MMD], timeout=1800),
        Step("browser", "verify_md_page.js",
             ["node", "verify_md_page.js", "md_with_diagram.html"], timeout=1800),
        Step("browser", "verify_pdf_moonbit.py",
             ["python", "verify_pdf_moonbit.py"], timeout=1800),
    ]


def spec_steps():
    return [
        Step("spec", "commonmark 0.31.2", ["node", os.path.join("tools", "commonmark_spec.js")],
             timeout=1800, verdict=conformance_verdict),
    ]


def collect(tiers, only):
    builders = {
        "env": env_steps,
        "build": build_steps,
        "gates": gate_steps,
        "browser": browser_steps,
        "spec": spec_steps,
    }
    steps = []
    for tier in tiers:
        steps.extend(builders[tier]())
    if only:
        steps = [s for s in steps if any(k in s.name for k in only)]
    return steps


def read_text(rel):
    with io.open(os.path.join(ROOT, rel), "r", encoding="utf-8",
                 errors="replace") as fh:
        return fh.read()


# --------------------------------------------------------------------------
# the release gate
# --------------------------------------------------------------------------

def module_version():
    """The version declared in moon.mod."""
    m = re.search(r'^\s*version\s*=\s*"([^"]+)"', read_text("moon.mod"), re.M)
    return m.group(1) if m else ""


def _git(*argv):
    proc = subprocess.run(["git"] + list(argv), cwd=ROOT,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return proc.returncode, proc.stdout.decode("utf-8", "replace").strip()


def release_gate(failed, ran, tiers, args):
    """The tag gate. Refuses unless every step that ran passed.

    The owner's instruction, verbatim: no tag before the local CI is green,
    "即便是我要求的" -- including when they ask for it directly. This function
    is the reason that promise is kept: it does not know who is asking, and the
    tag is produced by `git tag`, not by an agent's judgement that the run was
    green enough.
    """
    print("")
    print("=" * 72)
    print("RELEASE GATE")
    print("=" * 72)

    _, remotes = _git("remote", "-v")
    have_github = "github.com" in remotes
    print("  gitee  : may be pushed at any time")
    print("  github : only after a green run AND a tag"
          + ("" if have_github else "  (no GitHub remote configured -- policy only)"))

    skipped = [t for t in OPT_IN_TIERS if t not in tiers]
    if skipped:
        # Not hidden: a green that quietly ignored half the suite is not green.
        print("  excluded from this run: %s" % ", ".join(skipped))

    _, tag_list = _git("tag", "-l")
    tags = tag_list.split()
    try:
        want = rel.next_tag(tags, module_version())
    except rel.TagError as exc:
        print("  tag    : CANNOT DETERMINE -- %s" % exc)
        return 1
    print("  newest tag : %s" % (max(tags) if tags else "(none)"))
    print("  next  tag  : %s" % want)

    if want in tags:
        print("")
        print("  REFUSED: tag %s already exists." % want)
        return 1

    try:
        rel.assert_tag_allowed(failed, ran, skipped)
    except rel.TagError as exc:
        print("")
        print("  REFUSED: %s" % exc)
        print("  no tag was created. This holds even when asked for explicitly:")
        print("  a tag asserts 'this exact tree was verified', so it is the last")
        print("  thing produced, never an exception.")
        return 1

    print("  green : every step that ran passed")
    if args.check_release and not args.tag:
        print("")
        print("  READY. Re-run with --tag to create %s." % want)
        return 0

    _, dirty = _git("status", "--porcelain")
    if dirty:
        print("")
        print("  REFUSED: the working tree is dirty; a tag would not name a")
        print("  reproducible state.")
        for line in dirty.splitlines()[:10]:
            print("    %s" % line)
        return 1

    code, _ = _git("tag", want)
    if code != 0:
        print("")
        print("  REFUSED: `git tag %s` failed." % want)
        return 1
    _, head = _git("rev-parse", "--short", "HEAD")
    print("")
    print("  TAGGED %s at %s" % (want, head))
    return 0


def push_all(tiers, args):
    """Push per policy: gitee at any time, github only from a green run with a tag."""
    print("")
    print("=" * 72)
    print("PUSH")
    print("=" * 72)

    green = args._green
    _, tags = _git("tag", "--points-at", "HEAD")
    tags_here = tags.split()
    try:
        rel.assert_push_target_allowed("origin", green, bool(tags_here))
    except rel.TagError as exc:
        print("  REFUSED origin: %s" % exc)
        return 1

    rc = 0
    for remote in ("origin", "github"):
        _, remotes = _git("remote", "-v")
        if remote == "github" and "github.com" not in remotes:
            print("  skip   github: no such remote")
            continue
        try:
            rel.assert_push_target_allowed(remote, green, bool(tags_here))
        except rel.TagError as exc:
            print("  REFUSED %s: %s" % (remote, exc))
            rc = 1
            continue
        code, _ = _git("push", remote, "main")
        print("  %-6s main  : %s" % (remote, "ok" if code == 0 else "FAILED"))
        if code != 0:
            rc = 1
            continue
        for tag in tags_here:
            code, _ = _git("push", remote, tag)
            print("  %-6s %-5s : %s" % (remote, tag, "ok" if code == 0 else "FAILED"))
            if code != 0:
                rc = 1
    return rc


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="moonbit_markdown local CI")
    ap.add_argument("--tiers", default="env,build,gates",
                    help="comma separated: " + ",".join(TIERS))
    ap.add_argument("--only", default="",
                    help="comma separated substrings to filter step names")
    ap.add_argument("--fail-fast", action="store_true")
    ap.add_argument("--json", default="", help="write a JSON report here")
    ap.add_argument("--list", action="store_true", help="list steps and exit")
    ap.add_argument("--self-check", action="store_true",
                    help="verify this engine's own pass/fail accounting")
    ap.add_argument("--tag", action="store_true",
                    help="create the next tag, but only if every step passed")
    ap.add_argument("--check-release", action="store_true",
                    help="report whether a tag would be allowed, and change nothing")
    ap.add_argument("--push", action="store_true",
                    help="push per policy: gitee at any time, github only when "
                         "green and tagged")
    args = ap.parse_args()
    args._green = False

    if args.self_check:
        return self_check()

    tiers = [t.strip() for t in args.tiers.split(",") if t.strip()]
    unknown = [t for t in tiers if t not in TIERS]
    if unknown:
        sys.stderr.write("unknown tier(s): %s\n" % ", ".join(unknown))
        return 2

    only = [s for s in args.only.split(",") if s]
    steps = collect(tiers, only)
    if not steps:
        sys.stderr.write("no steps matched\n")
        return 2

    print("steps: %d   tiers: %s" % (len(steps), ",".join(tiers)))
    if args.list:
        for s in steps:
            print("  %-8s %s" % (s.tier, s.name))
        left = [t for t in OPT_IN_TIERS if t not in tiers]
        if left:
            print("")
            print("not run (opt-in): %s" % ", ".join(left))
            print("  python ci/ci.py --tiers %s" % ",".join(left))
        return 0

    start = time.time()
    failed = []
    for s in steps:
        ok = run_step(s)
        print("  %-4s %-8s %-34s %-30s %6.1fs"
              % (STATUS_ICON[s.status], s.tier, s.name, s.detail, s.seconds))
        sys.stdout.flush()
        if not ok:
            failed.append(s)
            print("")
            print(s.tail)
            print("")
            if args.fail_fast:
                break

    elapsed = time.time() - start
    ran = [s for s in steps if s.status != "skipped"]
    passed = [s for s in ran if s.status == "passed"]
    args._green = not failed

    print("")
    print("=" * 72)
    print("CI %s: %d/%d steps passed in %.1fs"
          % ("PASS" if not failed else "FAIL", len(passed), len(ran), elapsed))
    if failed:
        for s in failed:
            print("  FAIL %s/%s -- %s" % (s.tier, s.name, s.detail))
    left = [t for t in OPT_IN_TIERS if t not in tiers]
    if left:
        print("  NOT RUN (opt-in): %s" % ", ".join(left))

    if args.json:
        target = args.json if os.path.isabs(args.json) else os.path.join(ROOT, args.json)
        directory = os.path.dirname(target)
        if directory and not os.path.isdir(directory):
            os.makedirs(directory)
        report = {
            "green": not failed,
            "tiers": tiers,
            "ran": len(ran),
            "passed": len(passed),
            "seconds": round(elapsed, 1),
            "not_run": left,
            "steps": [s.as_dict() for s in ran],
        }
        with io.open(target, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(report, indent=2, ensure_ascii=False))
        print("report: %s" % os.path.relpath(target, ROOT))

    rc = 0 if not failed else 1

    if args.tag or args.check_release:
        rc = release_gate(failed, ran, tiers, args)
    if args.push and rc == 0:
        rc = push_all(tiers, args)
    return rc


# --------------------------------------------------------------------------
# self-check
# --------------------------------------------------------------------------

def self_check():
    """The engine must not be able to disagree with itself.

    Every CI bug worth this file's attention is a summary that disagrees with
    the process status, so the summary is what gets tested. Nothing here
    touches the working tree.
    """
    failures = []

    steps_dir = os.path.join(ARTIFACT_DIR, "steps")
    try:
        preexisting = set(os.listdir(steps_dir))
    except OSError:
        preexisting = set()
    probes = []

    def case(name, step, want_status):
        probes.append(step)
        run_step(step)
        if step.status != want_status:
            failures.append("%s: status %s, wanted %s"
                            % (name, step.status, want_status))

    case("silent success", Step("self", "ok", ["cmd", "/c", "exit", "0"]), "passed")
    case("nonzero exit", Step("self", "bad", ["cmd", "/c", "exit", "1"]), "failed")
    case("missing command", Step("self", "ghost", ["definitely-not-a-command-xyz"]),
         "failed")
    # exit 0 with a FAIL line in the output is not a pass.
    case("exit 0 but prints FAIL",
         Step("self", "liar", ["cmd", "/c", "echo [FAIL] something"]), "failed")
    # exit 0 having run nothing is not a pass either.
    case("vacuous pass",
         Step("self", "zero", ["cmd", "/c", "echo Total tests: 0, passed: 0"],
              zero_work_guard=True), "failed")
    # A verdict that reads a number: below the floor is red, at the floor is green.
    case("verdict below floor",
         Step("self", "spec-low", ["cmd", "/c", "echo conformance: 1/652"],
              verdict=conformance_verdict), "failed")
    case("verdict missing number",
         Step("self", "spec-none", ["cmd", "/c", "echo nothing here"],
              verdict=conformance_verdict), "failed")

    # The full-output capture, on the case it exists for: a step that fails
    # after printing more than the tail keeps.
    long_step = Step("self", "selfcheck-probe",
                     ["cmd", "/c", "for /L %i in (1,1,40) do @echo PROBE_LINE%i & exit /b 1"])
    probes.append(long_step)
    run_step(long_step)
    probe_path = os.path.join(ARTIFACT_DIR, "steps", long_step.log)
    kept = ""
    if os.path.isfile(probe_path):
        with io.open(probe_path, encoding="utf-8", errors="replace") as fh:
            kept = fh.read()
        os.remove(probe_path)
    else:
        failures.append("full output: no log for a failing step")
    if "PROBE_LINE1" not in kept:
        failures.append("full output: the line the tail drops is not in the log")

    total = 7
    failures.extend(release_self_check())
    total += release_self_check_count

    print("self-check: %d/%d cases passed" % (total - len(failures), total))
    for f in failures:
        print("  FAIL %s" % f)

    try:
        for name in set(os.listdir(steps_dir)) - preexisting:
            os.remove(os.path.join(steps_dir, name))
    except OSError as exc:
        sys.stderr.write("self-check could not sweep %s: %s\n" % (steps_dir, exc))

    if failures:
        print("ENGINE SELF-CHECK FAILED -- do not trust a CI run from this build")
        return 1
    print("ENGINE SELF-CHECK OK")
    return 0


def release_self_check():
    """The tag gate is the one promise that must hold against the owner.

    These cases are pure functions, so they run with no repository, no tag and
    no network -- and they are the reason the gate can be trusted to refuse
    later.
    """
    bad = []

    def want(name, got, expected):
        if got != expected:
            bad.append("%s: got %r, wanted %r" % (name, got, expected))

    # Only the final component moves.
    want("v0.1.0 -> v0.1.1", rel.next_tag(["v0.1.0"]), "v0.1.1")
    want("v0.1.9 -> v0.1.10", rel.next_tag(["v0.1.9"]), "v0.1.10")
    want("v1.2.3 -> v1.2.4", rel.next_tag(["v1.2.3"]), "v1.2.4")
    # Zero padding of the replaced component is preserved.
    want("v1.09 -> v1.10", rel.next_tag(["v1.09"]), "v1.10")
    want("v1.09 -> keeps width", rel.next_tag(["v1.09", "v1.10"]), "v1.11")
    # The newest tag is the one that moves, not the last created.
    want("newest wins", rel.next_tag(["v0.1.5", "v0.1.9", "v0.1.2"]), "v0.1.10")
    # A date-shaped tag follows the same rule.
    want("date-shaped tag", rel.next_tag(["release-2026-10"]), "release-2026-11")
    # The first tag comes from the module version, so nobody types it by hand.
    want("first tag from version", rel.next_tag([], "0.1.0"), "v0.1.0")
    # Refusing to invent a scheme beats guessing one.
    for name, tags, version in (("no tags, no version", [], None),
                                ("no trailing digits", ["nightly"], None)):
        try:
            rel.next_tag(tags, version)
            bad.append("%s: should have refused" % name)
        except rel.TagError:
            pass
    # The core promise: a failed step blocks the tag, always.
    ok_step = Step("self", "ok", ["cmd", "/c", "exit", "0"])
    run_step(ok_step)
    bad_step = Step("self", "bad", ["cmd", "/c", "exit", "1"])
    run_step(bad_step)
    try:
        rel.assert_tag_allowed([bad_step], [ok_step, bad_step], [])
        bad.append("failed step did not block the tag")
    except rel.TagError:
        pass
    # An empty run verifies nothing, so it cannot green-light a tag.
    try:
        rel.assert_tag_allowed([], [], [])
        bad.append("empty run did not block the tag")
    except rel.TagError:
        pass
    # All green, with an excluded tier reported rather than hidden.
    try:
        rel.assert_tag_allowed([], [ok_step], ["spec"])
    except rel.TagError as exc:
        bad.append("green run was refused: %s" % exc)
    # Push policy: gitee always, github only when green and tagged.
    try:
        rel.assert_push_target_allowed("origin", False, False)
    except rel.TagError as exc:
        bad.append("gitee was refused on a red run: %s" % exc)
    for name, green, tagged in (("github on red", False, True),
                                ("github untagged", True, False)):
        try:
            rel.assert_push_target_allowed("github", green, tagged)
            bad.append("%s: should have refused" % name)
        except rel.TagError:
            pass
    try:
        rel.assert_push_target_allowed("github", True, True)
    except rel.TagError as exc:
        bad.append("github was refused when green and tagged: %s" % exc)
    try:
        rel.assert_push_target_allowed("elsewhere", True, True)
        bad.append("unknown remote: should have refused")
    except rel.TagError:
        pass

    return bad


# The number printed by self_check(). Counted explicitly rather than computed
# from the calls above, so a case that is added without bumping the count shows
# up as a wrong total instead of hiding.
release_self_check_count = 20


if __name__ == "__main__":
    sys.exit(main())
