#!/usr/bin/env python3
"""Compare the MoonBit PDF with the reference PDF, page by page."""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

from pypdf import PdfReader

# The repository root: wherever this script sits. The reference PDF and the
# MoonBit PDF are both build products of this directory, so the paths follow
# the script rather than any one machine's layout.
ROOT = Path(__file__).resolve().parent
REF = ROOT / "moonbit_doubleML_state_diagram.pdf"
NEW = ROOT / "moonbit_doubleML_state_diagram_moonbit.pdf"

failures: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f"  -> {detail}" if detail else ""))
    if not cond:
        failures.append(name)


def page_text(r: PdfReader) -> list[str]:
    out = []
    for p in r.pages:
        try:
            out.append(p.extract_text() or "")
        except Exception:
            out.append("")
    return out


def main() -> int:
    for f in (REF, NEW):
        if not f.exists():
            print(f"MISSING: {f}")
            return 2

    rr = PdfReader(str(REF))
    rn = PdfReader(str(NEW))
    print(f"reference: {len(rr.pages)} pages, {REF.stat().st_size} bytes")
    print(f"moonbit:   {len(rn.pages)} pages, {NEW.stat().st_size} bytes")
    for r, tag in ((rr, "reference"), (rn, "moonbit")):
        b = r.pages[0].mediabox
        print(f"  {tag} page size: {float(b.width)/72*25.4:.1f} x {float(b.height)/72*25.4:.1f} mm")

    check("the page count matches the reference", len(rn.pages) == len(rr.pages),
          f"{len(rn.pages)} vs {len(rr.pages)}")
    b = rn.pages[0].mediabox
    check("the sheets are A4 portrait", 200 < float(b.width)/72*25.4 < 220 and 290 < float(b.height)/72*25.4 < 305,
          f"{float(b.width)/72*25.4:.1f}x{float(b.height)/72*25.4:.1f}mm")

    tref = page_text(rr)
    tnew = page_text(rn)

    # blank pages
    blank = [i + 1 for i, t in enumerate(tnew) if len(t.strip()) < 20]
    check("no blank pages", not blank, f"{len(blank)} blank: {blank[:12]}")
    blank_ref = [i + 1 for i, t in enumerate(tref) if len(t.strip()) < 20]
    print(f"  reference blank pages: {len(blank_ref)}")

    full_new = "\n".join(tnew)
    full_ref = "\n".join(tref)
    print(f"text layer: reference {len(full_ref)} chars, moonbit {len(full_new)} chars")

    check("the cover carries the target", "riantr/moonbit_doubleML" in full_new)
    check("the cover carries the metadata", "moonbit" in full_new and "0.1.20261012" in full_new)
    check("the actionable finding is in the text layer", "OperatorMismatch" in full_new)
    check("the notice data is in the text layer", "ParseError" in full_new)
    check("the appendices are there", "Appendix A" in full_new and "Appendix B" in full_new)
    check("the key map table is there", "region of the real diagram" in full_new)
    check("the notice list page is there", "NOTICE states of this file" in full_new)

    # the key map numbers, which come from the measured geometry
    for probe in ("16,302", "23.2:1", "7709", "16259", "11849", "11,540", "2147"):
        check(f"the measured geometry is in the document: {probe}", probe in full_new,
              "found" if probe in full_new else "MISSING")
    # the same probes on the reference, for the comparison
    print("the same probes on the reference:")
    for probe in ("16,302", "23.2:1", "7709", "16259", "11849", "11,540", "2147"):
        print(f"  {probe!r}: {'yes' if probe in full_ref else 'no'}")

    # source coverage: every file id and every notice state must appear
    print("checking source coverage against the .mmd ...")
    src = (ROOT / "riantr-moonbit_doubleML_0.164.28_0.1.20261012_20261023T005706Z.mmd").read_text(encoding="utf-8")
    file_ids = sorted(set(re.findall(r"scan --> (f\d+) :", src)))
    notice_states = sorted(set(re.findall(r'as (f\d+_n\d+)\s*$', src, re.M)))
    missing_files = [f for f in file_ids if f not in full_new]
    missing_states = [s for s in notice_states if s not in full_new]
    print(f"  file ids: {len(file_ids)}, missing from the PDF: {len(missing_files)} {missing_files[:5]}")
    print(f"  notice states: {len(notice_states)}, missing from the PDF: {len(missing_states)} {missing_states[:5]}")
    check("every file id is in the document", not missing_files)
    check("every notice state is in the document", not missing_states)

    # the same probes on the reference, for the comparison
    print("the same probes on the reference:")
    for probe in ("16,302", "23.2:1", "7709", "16259", "11849", "11,540", "2147"):
        print(f"  {probe!r}: {'yes' if probe in full_ref else 'no'}")

    # page by page: how much of the text is identical?
    def norm(s: str) -> str:
        return re.sub(r"\s+", " ", s).strip()

    def squish(s: str) -> str:
        # the same, but with every space removed: the drawings are scaled
        # differently, so the text layer breaks the same label into different
        # runs, and the runs carry different spacing
        return re.sub(r"\s+", "", s)

    same = 0
    same_squish = 0
    differ = []
    differ_squish = []
    for i in range(min(len(tref), len(tnew))):
        if norm(tref[i]) == norm(tnew[i]):
            same += 1
        else:
            differ.append(i + 1)
        if squish(tref[i]) == squish(tnew[i]):
            same_squish += 1
        else:
            differ_squish.append(i + 1)
    n = min(len(tref), len(tnew))
    print(f"pages whose text is identical: {same}/{n}")
    print(f"pages whose text is identical ignoring spaces: {same_squish}/{n}")
    print(f"pages whose text differs: {differ[:20]}{' ...' if len(differ) > 20 else ''}")
    print(f"pages whose text differs ignoring spaces: {differ_squish}")
    for p in differ[:6]:
        a = norm(tref[p - 1])
        b = norm(tnew[p - 1])
        # the first place the two texts part company
        k = 0
        while k < min(len(a), len(b)) and a[k] == b[k]:
            k += 1
        print(f"  p{p}: ref ...{a[max(0,k-40):k+60]!r}")
        print(f"       new ...{b[max(0,k-40):k+60]!r}")
    # the two differences are deliberate: the cover title comes from the
    # source instead of being hard-coded, and the enlarged page's caption
    # carries the file's path like the key map's caption does
    check("all but the two deliberate pages carry the same text", same_squish >= n - 2,
          f"{same_squish}/{n} identical")
    check("the pages that differ are the cover and the enlarged finding",
          differ_squish == [1, 22], f"differing: {differ_squish}")

    # per-page first line, side by side, to show the layout matches
    print("page-by-page first line:")
    diff = 0
    for i in range(min(len(tref), len(tnew))):
        a = (tref[i].strip().splitlines() or [""])[0][:70]
        b = (tnew[i].strip().splitlines() or [""])[0][:70]
        if a != b:
            diff += 1
            if diff <= 12:
                print(f"  p{i+1:>3} ref : {a!r}")
                print(f"       new : {b!r}")
    print(f"  pages whose first line differs: {diff}/{min(len(tref), len(tnew))}")

    print()
    if failures:
        print("FAILURES:\n  " + "\n  ".join(failures))
        return 1
    print("ALL PDF COMPARISON CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
