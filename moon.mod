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

// native is the preferred target: the command line tool drives a headless
// browser to rasterise Mermaid diagrams and to print the paginated document
// to PDF, and that is what a machine runs it on.
//
// The module is not native-only. It builds and runs on js, wasm and wasm-gc
// as well; what differs between the targets is the file and process layer
// under src/mdcli, which brings one file per target. The wasm-gc host cannot
// start another program, so the commands that drive a browser report that
// there. `ci/check_targets.py` verifies all four targets.

preferred_target = "native"

// No dependency is declared here: the async runtime this module needs comes
// with the toolchain, as `moonbitlang/core/async`. It is not a package that
// is downloaded from the registry and pinned to a version, so there is
// nothing to pin and nothing to upgrade - the runtime is whatever the
// toolchain carries, and the code is written against that one.
