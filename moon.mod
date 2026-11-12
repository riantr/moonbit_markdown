// module: riantr/moonbit_markdown — a Markdown/Mermaid -> HTML5 -> PDF
// toolchain, in MoonBit.
//
// The pipeline this module carries over from the reference implementation
// (build_final.py + build_pdf.js) is:
//
//   .md / .mmd  ->  AST  ->  HTML5  ->  (browser)  ->  paginated PDF
//
// Three design decisions worth stating up front:
//
// 1. The pure packages (src/md, src/mermaid, src/printpdf) have NO
//    dependencies and build for native / js / wasm alike, so the same code
//    runs in a browser (render markdown to HTML5 on the client) and in a
//    command line tool.
// 2. The browser is a RENDERER, not part of the algorithm. Mermaid's layout
//    engine and Chrome's PDF engine stay where they are; MoonBit owns the
//    parsing, the splitting strategy, the pagination maths and the page
//    assembly. That is the same division of labour the reference
//    implementation used, with the algorithm moved into MoonBit.
// 3. Nothing here is allowed to silently drop source data. The counts in a
//    scan report (files / states / notices) are recomputed from the parsed
//    source and printed next to the numbers the source itself claims, so a
//    discrepancy shows up as a discrepancy instead of disappearing.
//
// Dependency direction: this module depends on nothing of the user's other
// modules; they may depend on it.

name = "riantr/moonbit_markdown"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/riantr/moonbit_markdown"

license = "MIT"

keywords = [
  "markdown",
  "mermaid",
  "html5",
  "pdf",
  "literate-markdown",
  "documentation",
  "static-site",
]

description = "Markdown and Mermaid to HTML5, and HTML5 to a paginated PDF, in MoonBit"

// native, not wasm: the command line tool drives a headless browser to
// rasterise Mermaid diagrams and to print the paginated document to PDF.
// The pure packages are target-agnostic; only src/mdcli needs a process
// runtime, and it is native-only by construction.

preferred_target = "native"

import {
  "moonbitlang/async@0.22.4",
}
