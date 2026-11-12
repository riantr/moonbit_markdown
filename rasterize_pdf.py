#!/usr/bin/env python3
"""Rasterize selected PDF pages to PNG so the rendering can be eyeballed."""

from __future__ import annotations

import sys
from pathlib import Path

import pymupdf

PDF = Path(r"D:\src\moon\moonbit_markdown\moonbit_doubleML_state_diagram.pdf")
OUT = Path(r"D:\src\moon\moonbit_markdown\shots_pdf")
PAGES = [int(x) for x in (sys.argv[1] if len(sys.argv) > 1 else "1,2,3,20,21,34,35,36").split(",")]

doc = pymupdf.open(PDF)
OUT.mkdir(parents=True, exist_ok=True)
print(f"pages: {doc.page_count}")

for n in PAGES:
    if n > doc.page_count:
        print(f"skip {n} (out of range)")
        continue
    page = doc[n - 1]
    pix = page.get_pixmap(dpi=110)
    p = OUT / f"page-{n:03d}.png"
    pix.save(p)
    # report ink coverage: a blank page is much smaller and has no text
    text = page.get_text().strip()
    print(f"page {n:3d}: {pix.width}x{pix.height}  text={len(text):5d} chars  -> {p.name} ({p.stat().st_size} B)")

# ink-coverage sweep over every page: flag pages with neither text nor drawings
blank = []
for i in range(doc.page_count):
    page = doc[i]
    t = page.get_text().strip()
    drawings = page.get_drawings()
    if len(t) < 20 and len(drawings) < 3:
        blank.append(i + 1)
print(f"\npages with almost no content: {len(blank)}")
if blank:
    print("  ", blank[:60])
else:
    print("   none - every page carries text or vector art")
