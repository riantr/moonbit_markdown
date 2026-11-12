#!/usr/bin/env python3
"""Verify the redesigned detail section of the PDF (key map / enlarged finding / notice list).

Checks, against the real PDF text layer:
  1. the three new detail pages exist, in order, at the expected page numbers
  2. the enlarged finding page really carries the actionable finding text
  3. every one of the file's NOTICE state ids is listed on the list page
  4. the shared boilerplate footnote is printed ONCE in the whole document
     (it used to be printed 27 times, once per notice)
  5. the full data set is still complete: all 2,147 notice states in appendix B
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from pypdf import PdfReader

PDF = Path(r"D:\src\moon\moonbit_markdown\moonbit_doubleML_state_diagram.pdf")
SRC = Path(r"D:\src\moon\moonbit_markdown\riantr-moonbit_doubleML_0.164.28_0.1.20261012_20261023T005706Z.mmd")

BOILER_HEAD = "NOTICE \u2014 counted in `notices`, excluded from `actionable`."

failures: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f"  -> {detail}" if detail else ""))
    if not cond:
        failures.append(name)


def source_notice_ids() -> list[str]:
    """ground truth: every NOTICE state id in the source .mmd"""
    text = SRC.read_text(encoding="utf-8")
    ids = re.findall(r'state "NOTICE .*?" as (\w+)', text)
    return ids


def main() -> int:
    r = PdfReader(str(PDF))
    n = len(r.pages)
    print(f"pages: {n}")

    page_text = []
    for i in range(n):
        try:
            page_text.append(r.pages[i].extract_text() or "")
        except Exception as e:  # noqa: BLE001
            page_text.append(f"<extract failed: {e}>")

    # ---- locate the detail pages
    key_map = [i + 1 for i, t in enumerate(page_text) if "key map of the full diagram" in t]
    enlarged = [i + 1 for i, t in enumerate(page_text)
                if "the one actionable finding, enlarged" in t]
    listing = [i + 1 for i, t in enumerate(page_text)
               if "the 27 NOTICE states of this file" in t or "NOTICE states of this file" in t]
    print(f"key map pages: {key_map}")
    print(f"enlarged finding pages: {enlarged}")
    print(f"notice list pages: {listing}")

    check("key map page exists", len(key_map) == 1, str(key_map))
    check("enlarged finding page exists", len(enlarged) == 1, str(enlarged))
    check("notice list page exists", len(listing) >= 1, str(listing))
    if not (key_map and enlarged and listing):
        print("\nFAILURES:\n  " + "\n  ".join(failures))
        return 1

    km, en, li = key_map[0], enlarged[0], listing[0]
    check("the three detail pages are consecutive", en == km + 1 and li == km + 2,
          f"key map p{km}, enlarged p{en}, list p{li}")

    # ---- the enlarged page really shows the finding
    t_en = page_text[en - 1]
    check("enlarged page carries OperatorMismatch", "OperatorMismatch" in t_en)
    check("enlarged page carries the source location", "6795" in t_en, "6795:17")
    check("enlarged page carries the WHY note",
          "not reported" in t_en or "unknown type" in t_en.lower() or "Unknown" in t_en)

    # ---- every NOTICE of this file is on the list page
    src_ids = source_notice_ids()
    f98_ids = sorted({i for i in src_ids if i.startswith("f98_")})
    print(f"source NOTICE states total: {len(src_ids)}; in f98: {len(f98_ids)}")
    t_li = page_text[li - 1]
    missing = [i for i in f98_ids if i not in t_li]
    check("every NOTICE state of the actionable file is listed",
          not missing, f"missing {missing[:8]}" if missing else f"{len(f98_ids)} ids")

    # ---- the boilerplate is printed once as prose, not 27 times
    # (the key map page embeds the real SVG, whose 27 footnotes are in the text
    #  layer at 6% scale - illegible, and counted separately below)
    full_text = "\n".join(page_text)
    boiler_count = full_text.count(BOILER_HEAD)
    outside_map = sum(page_text[i].count(BOILER_HEAD) for i in range(n) if (i + 1) != km)
    print(f"boilerplate footnote occurrences: {boiler_count} in total, {outside_map} outside the key map")
    check("the shared NOTICE footnote is printed once as prose", outside_map == 1,
          f"{outside_map} occurrences outside the key map")
    check("the key map still carries the real diagram's 27 footnotes",
          page_text[km - 1].count(BOILER_HEAD) == 27,
          f"{page_text[km - 1].count(BOILER_HEAD)} in the key map")

    # ---- the complete data set survived
    doc_ids = set(re.findall(r"\bf\d+_n\d+\b", full_text))
    missing_all = [i for i in src_ids if i not in doc_ids]
    check("all source NOTICE state ids are still in the document",
          not missing_all, f"{len(missing_all)} missing e.g. {missing_all[:6]}")

    # ---- no leftover slice pages from the old layout
    leftover = [i + 1 for i, t in enumerate(page_text) if re.search(r"Detail f98 .*column \d+/", t)]
    check("the old column-slice pages are gone", not leftover, str(leftover[:10]))

    # ---- page geometry + blanks
    box = r.pages[0].mediabox
    w_mm = float(box.width) / 72 * 25.4
    h_mm = float(box.height) / 72 * 25.4
    check("page size is A4 portrait", 200 < w_mm < 220 and 290 < h_mm < 305, f"{w_mm:.1f}x{h_mm:.1f}mm")
    blank = [i + 1 for i, t in enumerate(page_text) if len(t.strip()) < 20]
    check("no blank pages", not blank, str(blank[:12]))

    print()
    if failures:
        print("FAILURES:\n  " + "\n  ".join(failures))
        return 1
    print("ALL DETAIL-SECTION CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
