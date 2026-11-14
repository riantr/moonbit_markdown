#!/usr/bin/env python3
"""ci/check_artifacts.py -- the structure gate for the generated documents.

## What this checks, and why it does not hash anything

The documents in the repository root are build products. The same source and
the same code produce the same drawing, but not the same bytes: the page
inlines the mermaid runtime, and the runtime is not pinned to a version, so
a page built with a different mermaid release is just as correct as the one
that is on disk -- and its hash is different. A pinned hash would therefore
promise something nobody can keep, and the promise would be broken by a
mermaid release rather than by a mistake.

So this gate checks the STRUCTURE of each document and the MEASUREMENTS the
document makes about itself:

  - the page carries the five JSON blocks its own client script reads;
  - the counts the page states about itself are the counts the tracked
    `.mmd` source produces when it is parsed the way `src/mermaid/parse.mbt`
    parses it;
  - the overview and the source the page embeds are the ones the generator
    would write for that source;
  - the counts the README states are the counts the document states.

None of that depends on the bytes of the mermaid runtime, so a document
built with any mermaid release gets the same verdict.

## Where the expectations come from

README.md states the numbers, in the table under "## The documents in the
root are generated":

    | document | files | notice states | notes | findings |
    | --- | --- | --- | --- | --- |
    | `moonbit_doubleML_state_diagram.html` | 221 | 2147 | 2371 | 1 |

A row in that table is a promise: the document must exist, and it must
contain what the row says it contains. The table is read out of README.md
rather than kept here, because the README is the one a human reads; if the
table cannot be read, this gate goes red rather than quietly checking
nothing.

## What it does not do

It does not regenerate the documents. It needs no browser, no network and no
mermaid runtime: it reads the documents that are already on disk and the
source that git tracks.
"""

import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, "README.md")

# The section of README.md that states what the generated documents must
# contain. Only the rows under this heading are promises; a table with the
# same shape elsewhere in the README is not one.
ANCHOR_RE = re.compile(r"^## The documents in the root are generated\s*$", re.M)

# | `name` | files | notice states | notes | findings |
ROW_RE = re.compile(
    r"^\|\s*`([^`]+)`\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*$",
    re.M,
)

# Every <script> element, with its attributes and its body.
SCRIPT_RE = re.compile(r"<script\b([^>]*)>(.*?)</script>", re.S)
ID_RE = re.compile(r'\bid="([^"]+)"')

# The em dash the generator writes in its labels.
EM = "\u2014"

# The smallest a mermaid runtime can plausibly be. The page has to carry one
# to work from file://, and every release of mermaid is orders of magnitude
# larger than this; a runtime that shrank to nothing would be a broken page.
MIN_RUNTIME_CHARS = 100000

# The four numbers a document is measured by, in the order the README table
# lists them.
MEASURES = ("files", "notice states", "notes", "findings")

# How many overview files go on one printed page. src/printpdf/layout.mbt
# calls it SLICE_FILES.
SLICE_FILES = 12


# --------------------------------------------------------------------------
# the source, parsed the way src/mermaid/parse.mbt parses it
# --------------------------------------------------------------------------

class StateDef(object):
    __slots__ = ("id", "msg")

    def __init__(self, sid, msg):
        self.id = sid
        self.msg = msg


class FileBlock(object):
    __slots__ = ("id", "path", "edge_label", "actionable", "notice_count",
                 "lines", "states", "notes")

    def __init__(self, ident, path, edge_label, actionable, notice_count,
                 lines, states, notes):
        self.id = ident
        self.path = path
        self.edge_label = edge_label
        self.actionable = actionable
        self.notice_count = notice_count
        self.lines = lines
        self.states = states
        self.notes = notes


class Diagram(object):
    __slots__ = ("meta", "files", "lines_total")

    def __init__(self, meta, files, lines_total):
        self.meta = meta
        self.files = files
        self.lines_total = lines_total


def is_space(ch):
    """src/text/text.mbt: is_space."""
    return ch in " \t\n\r"


def is_digit(ch):
    """src/text/text.mbt: is_ascii_digit."""
    return "0" <= ch <= "9"


def trimmed(s):
    """src/text/text.mbt: trimmed."""
    a = 0
    b = len(s)
    while a < b and is_space(s[a]):
        a += 1
    while b > a and is_space(s[b - 1]):
        b -= 1
    return s[a:b]


def leading_spaces(s):
    """src/text/text.mbt: leading_spaces."""
    n = 0
    while n < len(s) and s[n] == " ":
        n += 1
    return n


def split_lines(s):
    """src/text/text.mbt: split_lines.

    LF, CRLF and CR all end a line, and a trailing newline does not add an
    empty line at the end.
    """
    out = []
    start = 0
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == "\n":
            out.append(s[start:i])
            i += 1
            start = i
            continue
        if ch == "\r":
            out.append(s[start:i])
            i += 1
            if i < n and s[i] == "\n":
                i += 1
            start = i
            continue
        i += 1
    if start < n:
        out.append(s[start:])
    return out


def parse_meta(lines):
    """src/mermaid/parse.mbt: parse_meta.

    One header line may carry several `key=value` pairs, so the body is split
    on whitespace and each piece is read as a pair. The first occurrence of a
    key wins.
    """
    meta = []
    for line in lines:
        t = trimmed(line)
        if not t.startswith("%%"):
            continue
        body = trimmed(t[2:])
        for piece in split_lines(body.replace(" ", "\n")):
            if not piece:
                continue
            i = piece.find("=")
            if i < 0:
                continue
            key = piece[:i]
            value = piece[i + 1:]
            if not any(k == key for k, _ in meta):
                meta.append((key, value))
    return meta


def scan_edge_id(line):
    """src/mermaid/parse.mbt: scan_edge_id."""
    if leading_spaces(line) != 4:
        return None
    t = trimmed(line)
    if not t.startswith("scan --> "):
        return None
    rest = t[9:]
    end = 0
    while end < len(rest) and rest[end] != " " and rest[end] != ":":
        end += 1
    ident = rest[:end]
    if len(ident) > 1 and ident[0] == "f" and all(is_digit(c)
                                                 for c in ident[1:]):
        return ident
    return None


def edge_label_of(line):
    """src/mermaid/parse.mbt: edge_label_of."""
    t = trimmed(line)
    i = t.find(": ")
    return t[i + 2:] if i >= 0 else ""


def count_before(label, word):
    """src/mermaid/parse.mbt: count_before."""
    i = 0
    n = len(label)
    while i < n:
        if is_digit(label[i]):
            start = i
            while i < n and is_digit(label[i]):
                i += 1
            rest = trimmed(label[i:])
            if rest.startswith(word):
                return int(label[start:i])
            continue
        i += 1
    return 0


def state_decl(t):
    """src/mermaid/parse.mbt: state_decl.

    Returns (id, message) or None. The first and the LAST quote of the line
    bound the message, exactly as the MoonBit parser reads them.
    """
    if not t.startswith("state \""):
        return None
    first = -1
    last = -1
    for i, ch in enumerate(t):
        if ch == "\"":
            if first < 0:
                first = i
            else:
                last = i
    if first < 0 or last <= first:
        return None
    msg = t[first + 1:last]
    rest = t[last + 1:]
    if not rest.startswith(" as "):
        return None
    ident = trimmed(rest[4:])
    if not ident:
        return None
    for ch in ident:
        if not (ch.isascii() and (ch.isalpha() or is_digit(ch) or ch == "_")):
            return None
    return (ident, msg)


def file_path_of(ident, lines):
    """src/mermaid/parse.mbt: file_path_of."""
    prefix = "state \"" + ident + " " + EM + " "
    for line in lines:
        t = trimmed(line)
        if t.startswith(prefix):
            rest = t[len(prefix):]
            i = rest.find("\" as ")
            return rest[:i] if i >= 0 else rest
    return ""


def parse_file_block(ident, label, lines):
    """src/mermaid/parse.mbt: parse_file_block."""
    path = file_path_of(ident, lines)
    states = []
    notes = []
    in_note = False
    owner = ""
    buf = []
    for line in lines:
        if in_note:
            if trimmed(line) == "end note":
                notes.append((owner, " ".join(buf)))
                buf = []
                in_note = False
                continue
            buf.append(trimmed(line))
            continue
        t = trimmed(line)
        if t.startswith("note right of "):
            in_note = True
            owner = t[15:]
            buf = []
            continue
        decl = state_decl(t)
        if decl is not None:
            states.append(StateDef(decl[0], decl[1]))
    return FileBlock(ident, path, label,
                     count_before(label, "actionable"),
                     count_before(label, "notice(s)"),
                     lines, states, notes)


def parse_diagram(src):
    """src/mermaid/parse.mbt: parse_diagram."""
    lines = split_lines(src)
    meta = parse_meta(lines)
    files = []
    i = 0
    while i < len(lines):
        ident = scan_edge_id(lines[i])
        if ident is None:
            i += 1
            continue
        label = edge_label_of(lines[i])
        block = [lines[i]]
        j = i + 1
        while j < len(lines):
            block.append(lines[j])
            done = (trimmed(lines[j]) == "}"
                    and leading_spaces(lines[j]) == 4)
            j += 1
            if done:
                break
        files.append(parse_file_block(ident, label, block))
        i = j
    return Diagram(meta, files, len(lines))


# --------------------------------------------------------------------------
# the model, as src/mermaid/model.mbt and src/mermaid/page.mbt see it
# --------------------------------------------------------------------------

def is_notice(msg):
    """src/mermaid/model.mbt: is_notice."""
    return msg.startswith("NOTICE ") and msg.startswith("NOTICE " + EM + " ")


def is_stage(msg):
    """src/mermaid/model.mbt: is_stage."""
    return (msg == "lexed"
            or msg.startswith("inspection 1/3")
            or msg.startswith("inspection 2/3")
            or msg.startswith("inspection 3/3"))


def is_file_label(ident, msg):
    """src/mermaid/model.mbt: is_file_label."""
    return msg.startswith(ident + " " + EM + " ")


def meta_of(d, key):
    """src/mermaid/model.mbt: meta_of."""
    for k, v in d.meta:
        if k == key:
            return v
    return ""


def drawn_states(d):
    """src/mermaid/page.mbt: drawn_states."""
    return sum(len(f.states) for f in d.files)


def drawn_notices(d):
    """src/mermaid/model.mbt: drawn_notices."""
    return sum(1 for f in d.files for s in f.states if is_notice(s.msg))


def drawn_notes(d):
    """src/mermaid/model.mbt: drawn_notes."""
    return sum(len(f.notes) for f in d.files)


def drawn_findings(d):
    """src/mermaid/model.mbt: drawn_findings."""
    n = 0
    for f in d.files:
        for s in f.states:
            if (not is_notice(s.msg) and not is_stage(s.msg)
                    and not is_file_label(f.id, s.msg)):
                n += 1
    return n


def file_name(path):
    """src/mermaid/page.mbt: file_name."""
    start = 0
    for i, ch in enumerate(path):
        if ch == "/":
            start = i + 1
    return path[start:]


def overview_source(d):
    """src/mermaid/page.mbt: overview_source."""
    parts = ["stateDiagram-v2\n    direction LR\n"]
    for f in d.files:
        parts.append("    state \"%s %s %s\" as %s\n"
                     % (f.id, EM, f.path, f.id))
    parts.append("    state \"scan %s %s\" as scan\n"
                 % (EM, meta_of(d, "target")))
    for f in d.files:
        parts.append("    scan --> %s : %d actionable, %d notice(s), parsed\n"
                     % (f.id, f.actionable, f.notice_count))
    return "".join(parts)


def file_source(f):
    """src/mermaid/page.mbt: file_source."""
    parts = ["stateDiagram-v2\n    direction TB\n"]
    for line in f.lines:
        parts.append(line)
        parts.append("\n")
    return "".join(parts)


def source_counts(d):
    """The four numbers the source produces, in the order MEASURES lists."""
    return {
        "files": len(d.files),
        "notice states": drawn_notices(d),
        "notes": drawn_notes(d),
        "findings": drawn_findings(d),
    }


def expected_files(d):
    """src/mermaid/page.mbt: files_json, as data rather than as text."""
    out = []
    for f in d.files:
        notices = [{"id": s.id, "msg": s.msg}
                   for s in f.states if is_notice(s.msg)]
        findings = [{"id": s.id, "msg": s.msg}
                    for s in f.states
                    if (not is_notice(s.msg) and not is_stage(s.msg)
                        and not is_file_label(f.id, s.msg))]
        out.append({
            "id": f.id,
            "path": f.path,
            "name": file_name(f.path),
            "actionable": f.actionable,
            "noticeCount": f.notice_count,
            "notices": notices,
            "findings": findings,
            "src": file_source(f),
        })
    return out


# --------------------------------------------------------------------------
# the documents
# --------------------------------------------------------------------------

def script_blocks(text):
    """Every <script> element: (id, is_json, body)."""
    out = []
    for m in SCRIPT_RE.finditer(text):
        attrs = m.group(1)
        mid = ID_RE.search(attrs)
        out.append((mid.group(1) if mid else None,
                    'type="application/json"' in attrs,
                    m.group(2)))
    return out


def json_blocks(text):
    """The <script type="application/json"> elements, keyed by their id."""
    out = {}
    for bid, is_json, body in script_blocks(text):
        if is_json and bid and bid not in out:
            out[bid] = body
    return out


def plain_blocks(text):
    """The <script> elements that are not JSON blocks."""
    return [body for (_bid, is_json, body) in script_blocks(text)
            if not is_json]


def check_scripts(text):
    """The runtime and the client script.

    The runtime is whatever mermaid release was inlined, so its bytes are not
    checked -- only that it is there and that it is big enough to be one.
    The client script is this repository's own code, so the call it makes
    into the runtime IS a contract and is checked.
    """
    problems = []
    plain = plain_blocks(text)
    # The client script is this repository's own code: it calls into the
    # runtime and it reads the page's own elements. The runtime is the
    # library, so it may well contain the text of the call -- what it cannot
    # contain is the page's element ids.
    clients = [b for b in plain
               if "mermaid.render(" in b and "getElementById(" in b]
    if len(clients) != 1:
        problems.append("expected one client script, found %d" % len(clients))
    if not plain:
        problems.append("the document inlines no script at all")
        return problems
    # The runtime is the big one. Which release it is does not matter, so it
    # is not compared with anything -- only its size is, because a runtime
    # that shrank to nothing could not draw the diagram.
    runtime = max(plain, key=len)
    if len(runtime) < MIN_RUNTIME_CHARS:
        problems.append("the inlined mermaid runtime is %d characters; a "
                        "runtime that small cannot draw anything"
                        % len(runtime))
    if "mermaid" not in runtime:
        problems.append("the inlined runtime does not define the "
                        "`mermaid` global the client script calls")
    return problems


def check_scan_page(text, d, source_text, readme):
    """The checks for one scan page. Returns a list of problems."""
    problems = []

    if text.count("<main>") != 1 or text.count("</main>") != 1:
        problems.append("expected exactly one <main> element, found %d"
                        % text.count("<main>"))

    blocks = json_blocks(text)
    for key in ("meta", "counts", "files", "overview-src", "raw-src"):
        if key not in blocks:
            problems.append("the page has no "
                            "<script type=\"application/json\" id=\"%s\"> block"
                            % key)
    if problems:
        return problems

    try:
        meta = json.loads(blocks["meta"])
        counts = json.loads(blocks["counts"])
        files = json.loads(blocks["files"])
        overview = json.loads(blocks["overview-src"])
        raw = json.loads(blocks["raw-src"])
    except ValueError as exc:
        problems.append("a JSON block does not parse: %s" % exc)
        return problems

    if not isinstance(meta, dict) or not isinstance(counts, dict):
        problems.append("the metadata and counts blocks are not objects")
        return problems
    if not isinstance(overview, str) or not isinstance(raw, str):
        problems.append("the overview and raw-source blocks are not strings")
        return problems

    # The header the source carries, as the page states it.
    want_meta = [[k, v] for k, v in d.meta]
    if [[k, v] for k, v in meta.items()] != want_meta:
        problems.append("the metadata block does not match the source header")

    # The counts the page states about itself, against the source.
    src = source_counts(d)
    page = {
        "files": counts.get("files"),
        "notice states": counts.get("drawnNotices"),
        "notes": counts.get("drawnNotes"),
        "findings": counts.get("drawnFindings"),
    }
    for key in MEASURES:
        if page[key] != src[key]:
            problems.append("the page states %s=%s, the source has %d"
                            % (key, page[key], src[key]))
    for key, want in (("claimedFiles", meta_of(d, "files")),
                      ("claimedNotices", meta_of(d, "notices")),
                      ("claimedFindings", meta_of(d, "actionable"))):
        if counts.get(key) != want:
            problems.append("the page states %s=%s, the source header says %s"
                            % (key, counts.get(key), want))

    # The source the page was built from, and the overview it embeds.
    if raw != source_text:
        problems.append("the source the page embeds is not the tracked "
                        "`.mmd` source")
    if overview != overview_source(d):
        problems.append("the overview the page embeds is not the overview "
                        "the source produces")

    # The per-file data the client script reads.
    problems.extend(check_files(files, d))

    # The runtime and the client script.
    problems.extend(check_scripts(text))

    # The README, the page and the source must say the same thing.
    problems.extend(check_readme(readme, src))

    return problems


def check_files(files, d):
    """The `files` block against the source, field by field."""
    problems = []
    want = expected_files(d)
    if not isinstance(files, list):
        return ["the files block is not a list"]
    if len(files) != len(want):
        return ["the files block holds %d entries, the source has %d"
                % (len(files), len(want))]
    for i, (got, expect) in enumerate(zip(files, want)):
        if not isinstance(got, dict):
            problems.append("files[%d] is not an object" % i)
            continue
        for key in ("id", "path", "name", "actionable", "noticeCount"):
            if got.get(key) != expect[key]:
                problems.append("files[%d].%s is %r, the source says %r"
                                % (i, key, got.get(key), expect[key]))
        for key in ("notices", "findings"):
            if got.get(key) != expect[key]:
                problems.append("files[%d].%s does not match the source" %
                                (i, key))
        if got.get("src") != expect["src"]:
            problems.append("files[%d].src is not the diagram the source "
                            "produces" % i)
    return problems


def check_readme(readme, src):
    """The counts the README states against the counts of the source."""
    problems = []
    for key in MEASURES:
        if readme[key] != src[key]:
            problems.append("README.md states %s=%d, the source has %d"
                            % (key, readme[key], src[key]))
    return problems


def count_rows(text, table_marker):
    """The number of body rows of the first table with that marker."""
    start = text.find(table_marker)
    if start < 0:
        return None
    end = text.find("</table>", start)
    if end < 0:
        return None
    body = text[start:end]
    tb = body.find("<tbody>")
    if tb < 0:
        return None
    te = body.find("</tbody>", tb)
    if te < 0:
        return None
    return body[tb + len("<tbody>"):te].count("<tr>")


def check_print_page(text, d, readme):
    """The checks for one print page. Returns a list of problems."""
    problems = []

    blocks = json_blocks(text)
    if "srcs" not in blocks:
        return ["the page has no "
                "<script type=\"application/json\" id=\"srcs\"> block"]

    try:
        srcs = json.loads(blocks["srcs"])
    except ValueError as exc:
        return ["the srcs block does not parse: %s" % exc]
    if not isinstance(srcs, list):
        return ["the srcs block is not a list"]

    # The sources the browser renders: one per overview slice, plus the
    # whole diagram and the focused diagram of the file with a finding.
    slices = 0
    start = 0
    while start < len(d.files):
        end = min(start + SLICE_FILES, len(d.files))
        slices += 1
        start = end
    has_detail = any(f.actionable > 0 for f in d.files)
    want_sources = slices + (2 if has_detail else 0)
    if len(srcs) != want_sources:
        problems.append("the page renders %d diagrams, the source needs %d"
                        % (len(srcs), want_sources))
    for i, s in enumerate(srcs):
        if not isinstance(s, str) or not s.strip():
            problems.append("diagram %d is not a diagram source" % i)
    # The overview slices are whole Mermaid diagrams; the two sources after
    # them are the file with a finding, whole and focused.
    for i in range(min(slices, len(srcs))):
        if not srcs[i].startswith("stateDiagram-v2"):
            problems.append("diagram %d is not an overview diagram" % i)

    # The numbers the page prints about itself.
    src = source_counts(d)
    sentences = [
        "The source is %d lines with %d states and %d notes"
        % (d.lines_total, drawn_states(d), drawn_notes(d)),
        "all %d files, their paths and finding counts" % src["files"],
        "all %d notice states, with their source locations"
        % src["notice states"],
    ]
    for sentence in sentences:
        if sentence not in text:
            problems.append("the page does not say \"%s\"" % sentence)

    # The findings the page lists, counted from the table it lists them in.
    rows = count_rows(text, "<table class=\"data\">")
    if rows is None:
        problems.append("the page has no findings table")
    elif rows != src["findings"]:
        problems.append("the page lists %d findings, the source has %d"
                        % (rows, src["findings"]))

    # The runtime and the print script.
    problems.extend(check_scripts(text))

    # The README and the source must say the same thing.
    problems.extend(check_readme(readme, src))

    return problems


# --------------------------------------------------------------------------
# the README contract
# --------------------------------------------------------------------------

def read_text(path):
    with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def contract_rows(text):
    """Every (document, files, notice states, notes, findings) the README
    promises, in document order."""
    anchor = ANCHOR_RE.search(text)
    if not anchor:
        raise ValueError("README.md no longer has a '## The documents in the "
                         "root are generated' section, so the table of "
                         "expectations cannot be located")
    rest = text[anchor.end():]
    nxt = re.search(r"^## ", rest, re.M)
    section = rest if not nxt else rest[:nxt.start()]
    rows = []
    for name, files, notices, notes, findings in ROW_RE.findall(section):
        rows.append((name, {
            "files": int(files),
            "notice states": int(notices),
            "notes": int(notes),
            "findings": int(findings),
        }))
    return rows


# --------------------------------------------------------------------------
# the source file
# --------------------------------------------------------------------------

def source_candidates():
    """The `.mmd` sources in the repository root."""
    out = []
    for name in sorted(os.listdir(ROOT)):
        if name.endswith(".mmd") and os.path.isfile(os.path.join(ROOT, name)):
            out.append(name)
    return out


def read_source(name):
    """The text of a source file, read as bytes so that nothing translates."""
    with io.open(os.path.join(ROOT, name), "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8", "replace")


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

def main():
    readme_text = read_text(README)
    try:
        rows = contract_rows(readme_text)
    except ValueError as exc:
        print("[FAIL] %s" % exc)
        return 1

    if not rows:
        print("[FAIL] README.md states no document to check, so this gate "
              "would verify nothing")
        print("       the table under '## The documents in the root are "
              "generated' must have a row per document:")
        print("       | document | files | notice states | notes | findings |")
        return 1

    candidates = source_candidates()
    if not candidates:
        print("[FAIL] no `.mmd` source in the repository root, so the counts "
              "the documents state cannot be derived")
        return 1

    # The source the documents were built from. When there is only one
    # candidate it is the source; when there are several, the page that
    # embeds its source says which one it is.
    chosen = None
    if len(candidates) == 1:
        chosen = candidates[0]
    else:
        for name, _readme in rows:
            path = os.path.join(ROOT, name)
            if not os.path.isfile(path):
                continue
            text = read_text(path)
            blocks = json_blocks(text)
            if "raw-src" not in blocks:
                continue
            try:
                raw = json.loads(blocks["raw-src"])
            except ValueError:
                continue
            for candidate in candidates:
                if read_source(candidate) == raw:
                    chosen = candidate
                    break
            if chosen:
                break
        if chosen is None:
            print("[FAIL] %d `.mmd` sources are in the repository root and "
                  "none of them is the one the documents were built from"
                  % len(candidates))
            for candidate in candidates:
                print("       %s" % candidate)
            return 1

    source_text = read_source(chosen)
    diagram = parse_diagram(source_text)
    counts = source_counts(diagram)

    print("source: %s -- %d files, %d notice states, %d notes, %d findings"
          % (chosen, counts["files"], counts["notice states"],
             counts["notes"], counts["findings"]))
    print("")

    bad = 0
    for name, readme in rows:
        path = os.path.join(ROOT, name)
        if not os.path.isfile(path):
            print("[FAIL] %s is missing" % name)
            print("       regenerate it, or delete the row from README.md")
            bad += 1
            continue
        text = read_text(path)
        if 'id="counts"' in text:
            problems = check_scan_page(text, diagram, source_text, readme)
        elif 'id="srcs"' in text:
            problems = check_print_page(text, diagram, readme)
        else:
            problems = ["the document is neither a scan page (it has no "
                        "id=\"counts\" block) nor a print page (it has no "
                        "id=\"srcs\" block)"]
        if problems:
            print("[FAIL] %s" % name)
            for problem in problems[:8]:
                print("       %s" % problem)
            if len(problems) > 8:
                print("       ... and %d more" % (len(problems) - 8))
            bad += 1
            continue
        print("[PASS] %s  files=%d notice states=%d notes=%d findings=%d"
              % (name, counts["files"], counts["notice states"],
                 counts["notes"], counts["findings"]))

    print("")
    if bad:
        print("[FAIL] %d of %d documents are not what README.md says they are"
              % (bad, len(rows)))
        return 1
    print("[PASS] all %d documents are what README.md says they are"
          % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
