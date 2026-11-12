#!/usr/bin/env python3
"""Verify the generated PDF: page count, page size, and text-layer coverage."""

from __future__ import annotations

import re
import sys
from pathlib import Path

from pypdf import PdfReader

# The PDF to check: the reference implementation's output, which is a build
# product of this directory. The path follows the script, so the tool works
# wherever the repository is checked out.
PDF = Path(__file__).resolve().parent / "moonbit_doubleML_state_diagram.pdf"

failures: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f"  -> {detail}" if detail else ""))
    if not cond:
        failures.append(name)


def main() -> int:
    r = PdfReader(str(PDF))
    n = len(r.pages)
    print(f"pages: {n}")

    box = r.pages[0].mediabox
    w_mm = float(box.width) / 72 * 25.4
    h_mm = float(box.height) / 72 * 25.4
    print(f"page size: {w_mm:.1f} x {h_mm:.1f} mm (A4 = 210 x 297)")

    check("PDF has a plausible page count", n >= 35, f"{n} pages")
    check("page size is A4 portrait", 200 < w_mm < 220 and 290 < h_mm < 305, f"{w_mm:.1f}x{h_mm:.1f}mm")

    # text layer coverage
    sample = list(range(0, min(n, 8))) + list(range(max(0, n - 4), n))
    texts: dict[int, str] = {}
    for i in sample:
        try:
            texts[i] = r.pages[i].extract_text() or ""
        except Exception as e:  # noqa: BLE001
            texts[i] = f"<extract failed: {e}>"

    full = "\n".join(texts.values())
    print(f"sampled {len(texts)} pages, extracted {len(full)} chars")

    check("cover carries the target", "riantr/moonbit_doubleML" in full)
    check("cover carries the metadata block", "moonbit" in full and "0.1.20261012" in full)
    check("the one actionable finding is in the text layer",
          "OperatorMismatch" in full, "found" if "OperatorMismatch" in full else "MISSING")
    check("notice data is in the text layer", "ParseError" in full)
    check("appendix header present", "Appendix" in full)

    # how many pages carry any text at all (blank-page detection)
    nonempty = 0
    blank = []
    for i in range(n):
        try:
            t = (r.pages[i].extract_text() or "").strip()
        except Exception:  # noqa: BLE001
            t = ""
        if len(t) > 20:
            nonempty += 1
        else:
            blank.append(i + 1)
    print(f"pages with text: {nonempty}/{n}")
    if blank:
        print(f"  pages with little/no text: {blank[:40]}{' ...' if len(blank) > 40 else ''}")
    check("no blank pages", not blank, f"{len(blank)} blank: {blank[:12]}")

    # images: the diagram slices should be vector, but check for XObjects too
    with_imgs = 0
    for i in range(n):
        try:
            res = r.pages[i].get("/Resources") or {}
            xo = res.get("/XObject")
            if xo is not None:
                with_imgs += 1
        except Exception:  # noqa: BLE001
            pass
    print(f"pages with XObject resources: {with_imgs}/{n}")

    print()
    if failures:
        print("FAILURES:\n  " + "\n  ".join(failures))
        return 1
    print("ALL PDF CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
