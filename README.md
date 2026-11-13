# riantr/moonbit_markdown

Markdown and Mermaid to HTML5, and HTML5 to a paginated PDF, in MoonBit.

This module carries over the algorithm of a reference implementation that
was written in Python and JavaScript:

```
.mmd / .md  ->  parse  ->  split  ->  HTML5  ->  (browser)  ->  PDF
```

The reference implementation and its output are kept next to this package in
the repository root, so the two can be compared directly:

| reference (Python / JS) | this package |
| --- | --- |
| `build_final.py` | `src/mermaid` + `src/md` |
| `build_pdf.js` | `src/printpdf` (the pagination maths) |

## Quick check

Six commands, six one-line verdicts. They need `node`, `python` with
`pypdf`, and a headless Chrome; nothing else.

```
python ci/ci.py                                # CI PASS: 7/7 steps passed
python ci/ci.py --tiers browser,spec           # the slow half, 4 more steps
moon check                                     # 0 errors, 0 warnings
moon test                                      # 86/86, failed: 0
python verify_pdf_moonbit.py                   # ALL PDF COMPARISON CHECKS PASSED
node verify_page.js moonbit_doubleML_state_diagram.html <in.mmd>
                                               # ALL PAGE CHECKS PASSED
```

`node verify_md_page.js md_with_diagram.html` checks the Markdown side and
prints `MD PAGE CHECKS PASSED`.

The two documents are large — the page is 5.9 MB and the PDF 7.3 MB, because
the mermaid runtime is inlined and the PDF carries 117 pages. The scripts
above read them for you and print a verdict; there is no need to open either
one to check the work.

In a fresh clone the documents are not there — they are build products, and
the section below says how to make each one. The quickest way to the
verdicts is:

```
node build_pdf.js                                        # the reference pdf
moon run . mmd2html <in.mmd> moonbit_doubleML_state_diagram.html
moon run . mmd2pdf  <in.mmd> moonbit_doubleML_state_diagram_moonbit.pdf
moon run . md2html  md_with_diagram.md md_with_diagram.html
```

## What is in here

| package | what it does | dependencies |
| --- | --- | --- |
| `src/text` | character-level text helpers | none |
| `src/md` | Markdown parser and HTML5 renderer | `src/text` |
| `src/mermaid` | Mermaid scan parser and self-contained page builder | `src/text` |
| `src/printpdf` | the print layout: the split, the pagination maths, the page assembly | `src/text`, `src/mermaid` |
| `src/mdcli` | the command line tool | `moonbitlang/async`, the pure packages |

The four pure packages have no dependencies and build for `native`, `js` and
`wasm` alike, so the same code can render Markdown to HTML5 in a browser.
Only the command line tool needs a process runtime, and it is native-only by
construction.

## Two facts that shape the design

**Mermaid cannot lay out the whole scan.** Mermaid's layout engine (dagre)
fails with `Cannot set properties of undefined (setting 'order')` once more
than about thirty compound states carry notes; measured, `<=30` files render
and `>=40` crash. Deleting the notes makes 221 files render, so the notes are
the trigger, not the node count. A monolithic drawing would be around 129 MB
even if it worked.

So the page is shipped SPLIT: one flat overview graph (no compound nesting,
which dagre can always lay out) plus one sub-diagram per file. **The
splitting decision is made here, in MoonBit** — the browser only runs mermaid
on the pieces it is given.

**The diagram is too wide to print as a drawing.** The actionable file's
diagram is 16,302 px wide. Sliced across A4 pages it needs thirteen sheets,
and the labels end up at roughly 8 px. Worse, the one finding sits at x=309
while the note that explains it sits at x=11,849 — nine sheets apart. So the
print layout does not slice the drawing; it prints a key map of the whole
strip, the finding enlarged from the real render, and the notices as a list.

## The command line tool

```
moon run . mmd2html   <in.mmd>  <out.html>    # a Mermaid scan to the page
moon run . md2html    <in.md>   <out.html>    # a Markdown document to a page
moon run . print2pdf  <in.html> <out.pdf>     # a page to PDF, via headless Chrome
moon run . mmd2pdf    <in.mmd>  <out.pdf>     # a scan to a paginated PDF
moon run . md2pdf     <in.md>   <out.pdf>     # a document to a paginated PDF
moon run . mmd2measure <in.mmd>               # the measured geometry, for checking
```

Options: `--mermaid-js <path>` (the mermaid runtime to inline),
`--chrome <path>` (the browser to drive), `--header-footer` (let the browser
print its own header and footer; off by default, because the document carries
its own margins).

Both paths have a default, and the defaults are the ones on the machine this
was written on — Chrome under `C:\Program Files`, the runtime inside the
mermaid-cli npm package. On another machine, pass the two options. A path that
does not exist is reported, not silently replaced by the default.

The browser is a rasteriser here, not part of the algorithm: the page is
already laid out, and Chrome only turns it into PDF pages.

Both kinds of document print as A4 portrait with 12 mm margins. The Mermaid
runtime is 2.6 MB, so a Markdown page only carries it when the document
actually holds a diagram; a document without one stays a few kilobytes.

`md_with_diagram.md` is a small document that exercises the Markdown side and
the Mermaid side at once.

### How a scan becomes a PDF

The print layout needs to know the geometry of the drawing it is printing —
where the finding is, where the notice fan is, how wide the strip is — and
that geometry only exists once a browser has laid the drawing out. So the
chain has three steps, and the algorithm is in the middle one:

1. **measure.** MoonBit writes a page that renders the actionable file's
   drawing and reports the geometry of every node; Chrome is asked for its
   DOM with `--dump-dom`, and the numbers come back as text.
2. **lay out.** MoonBit reads that geometry back and computes the document:
   the cover, the nineteen overview slices, the key map with its tick marks,
   the enlarged finding, the notice list and the two appendices. Every number
   in the document — the pixel ranges, the scale, the distance between the
   finding and the note that explains it — is computed here.
3. **print.** MoonBit writes the laid-out page; Chrome renders the drawings
   into it and prints it to PDF with `--print-to-pdf`.

The browser measures and rasterises. It decides nothing: if the browser
answered with nothing, the tool says so and writes no PDF rather than
printing an empty document.

The same rule holds for the mermaid runtime. A page that needs it and cannot
get it is not written at all: the scan page is a mermaid application, so
without the runtime there would be nothing to draw, and a document whose
diagram would only show its source would be a broken document under the name
the caller asked for. A document without a diagram never needs the runtime,
so it is never touched by a missing one.

**Exit codes:** MoonBit exposes no process-exit entry point in the packages
available here, so a failure prints an `ERROR` line and the process still
exits 0. A caller must read the output, not the exit code. The same
limitation is recorded in `riantr/moonbit_static_analysis`.

## A note on strings

MoonBit's `String` is UTF-16: `s[i]` yields a `UInt16` code unit and
`s.length()` counts code units, not characters. A character outside the basic
plane — an emoji, say — is two code units, so every index after it is one
more than the character index. Slicing at a code unit boundary can also cut a
surrogate pair in half, which turns one character into two broken ones.

Every part of this package that reasons about characters works on
`Array[Char]` instead (`src/text`), so no slice can break a character.
`src/text` also has `slice(s, from, to)`, which takes CHARACTER indices, for
the places where a substring has to be cut out of a string that was scanned
as characters.

The distinction is not academic: a state label with an emoji in it used to
shift every index after the emoji, and the parser then dropped the state
because the ` as id` behind it was no longer where it looked. There are
regression tests for exactly that.

## How close to CommonMark is the Markdown parser?

Measured against the [CommonMark 0.31.2 spec](https://spec.commonmark.org/0.31.2/spec.json)
— its 652 examples, each rendered and compared with the expected HTML:

```
node tools/commonmark_spec.js          # render every example and compare
node tools/commonmark_spec.js --show Links 5   # the examples of one section
```

The script downloads the spec and the reference implementation's entity table
on the first run and keeps them in `tools/commonmark/`, which is not part of
the repository. The two sides are reduced to the same form before they are
compared — the whitespace between the tags carries no meaning, the attributes
that matter are kept, and the character references are decoded on both sides.

The HTML5 table of the named character references in `src/md/entity.mbt` is
generated as well: `node tools/gen_entity_table.js` writes it from the
reference implementation's table, so that the two thousand names do not have
to be typed by hand.

**575 of the 652 examples agree (88.2 %).** The sections that agree completely:
thematic breaks, ATX headings, indented and fenced code, HTML blocks, link
reference definitions (26 of 27), paragraphs, blank lines, block quotes, list
items, code spans, images, autolinks, raw HTML, backslash escapes, the HTML5
character references, hard and soft line breaks, and the textual content.

What is left is stated rather than hidden:

| section | | |
| --- | --- | --- |
| emphasis and strong emphasis | 75/132 | the full delimiter-stack algorithm of the spec — the "rule of three" and the nesting of emphasis — is not implemented; the parser pairs an opener with the next closer that fits |
| links | 78/90 | the same, and the cases where the text of a link holds an unfinished HTML tag |
| lists | 22/26 | a list whose item holds a nested list with a blank line inside it is called loose when the spec calls it tight |
| tabs | 9/11 | the tab stops inside a list item are counted in columns, not in tab stops |
| setext headings, link reference definitions | 26/27 each | one case each |

The report of the script lists the examples that differ, section by section,
which is the honest measure of what is left.

## Tests

```
moon test            # the whole module
moon test src/md     # one package
```

## Verifying the output

Three scripts check this package's own output against the reference
implementation's:

```
node verify_page.js moonbit_doubleML_state_diagram.html <in.mmd>
node verify_md_page.js <a markdown page with a diagram>
python verify_pdf_moonbit.py
```

Every path in these scripts is relative to the script itself, so they work in
a clone wherever it is put. The three external tools they need are looked up
in one place, in `env.js`: the browser, the mermaid runtime and puppeteer.
Each is found in the same order — an environment variable first, then the
usual places for the platform — and the environment variables are:

| variable | what it names |
| --- | --- |
| `CHROME` | the Chrome or Edge binary to drive |
| `MERMAID_JS` | the `mermaid.min.js` runtime to inline |
| `PUPPETEER_MODULE` | the puppeteer module to load |

Without `CHROME` the usual install locations are tried, and if none has one
the browser puppeteer downloaded is used. Puppeteer is looked for in the
repository's own `node_modules` first, then in the global npm root.

The MoonBit tool has the same three settings, under the names it was given
there: `--chrome`, `--mermaid-js`, and its own default paths.

`verify_page.js` opens the page in a real browser and checks the drawing: the
node count of the overview, the sidebar, the drawn notice and finding counts,
that clicking a file renders its own diagram, and that nothing is written to
the console.

`verify_pdf_moonbit.py` compares the PDF with the reference PDF: the page
count, the paper size, the blank pages, the presence of every file id and
every notice state of the source, the numbers that came out of the
measurement, and the text of every page.

`verify_md_page.js` opens a Markdown page in a real browser and checks that
its diagram was rendered into an SVG, that the headings, tables and lists are
there, and that nothing was written to the console.

The reference implementation's own checking tools are kept next to them, and
they look at the REFERENCE output, not this package's: `verify_pdf.py` and
`verify_detail.py` check `moonbit_doubleML_state_diagram.pdf`, and
`rasterize_pdf.py` rasterises that PDF's pages to PNG for a visual look.

## The documents in the root are generated

Every `.html` and `.pdf` in the repository root is a build product, and all of
them can be produced again from the sources:

```
moon run . mmd2html <in.mmd> moonbit_doubleML_state_diagram.html
moon run . mmd2pdf  <in.mmd> moonbit_doubleML_state_diagram_moonbit.pdf
moon run . md2html  md_with_diagram.md md_with_diagram.html
moon run . md2pdf   md_with_diagram.md md_with_diagram.pdf
node build_pdf.js                          # the REFERENCE pdf
```

`moon run . mmd2pdf` writes the laid-out page next to the PDF, as
`<name>.print.html`. The reference PDF is produced by `node build_pdf.js`,
which is the reference implementation's own script.

Deleting these files loses nothing but bytes: the two documents whose content
is pinned can be checked by their hash, and the build reproduces both of them
byte for byte.

| document | SHA256 |
| --- | --- |
| `moonbit_doubleML_state_diagram.html` | `92DF5501451B515599A278E992A38534B1D3C0FD136B898CF7C174B5748BFFB0` |
| `moonbit_doubleML_state_diagram_moonbit.print.html` | `332BCCC250674F881EEAAB4EE4CB94BC693D5FBAFBE09C592935260C722D22EB` |

The PDFs have no pinned hash: Chrome writes a timestamp into every one of
them, so each run differs. Compare their CONTENT with
`verify_pdf_moonbit.py`.

Each package also carries a `pkg.generated.mbti`: the generated public
interface of that package, the file `moon info` writes. It belongs to the
package and travels with it when the module is published, so it is kept in
the tree rather than treated as build noise. It is deterministic — running
`moon info` again reproduces it byte for byte.

## Releasing

The tag is the one artefact that says "this exact tree was tested", so it is
the last thing produced and never an exception. `ci/release.py` holds that
promise as three rules, and `ci/ci.py` is the only thing that acts on them:

- **No tag while the local CI is red.** Not even on request.
- **A tag only moves its final component**: `v0.1.0` → `v0.1.1` → `v0.1.2`.
- **Gitee may be pushed at any time; GitHub only from a green run that has a
  tag**, so what is published there is always a named, tested state.

```
python ci/ci.py --self-check                    # 27/27: the engine's own accounting
python ci/ci.py                                 # env + build + gates (fast, portable)
python ci/ci.py --tiers env,build,gates,browser,spec --check-release
                                                # would a tag be allowed? changes nothing
python ci/ci.py --tiers env,build,gates,browser,spec --tag --push
```

| tier | what it runs | needs |
| --- | --- | --- |
| `env` | `moon`, `node`, `python` versions | nothing |
| `build` | `moon check`, `moon test`, the four pure packages on all four targets | nothing |
| `gates` | `ci/check_artifacts.py`: the hashes pinned in the table above | the generated documents |
| `browser` | `verify_page.js`, `verify_md_page.js`, `verify_pdf_moonbit.py` | Chrome, the generated documents |
| `spec` | `tools/commonmark_spec.js`, against the floor this README states | the spec download |

The default run is `env,build,gates` because it is portable — no browser, no
network — and it is what a tag is normally granted from. The two opt-in tiers
are slow, and when they are left out the tag gate **names them** rather than
silently dropping them: a green that quietly ignored the browser checks is not
green. A full release points at all five.

The engine exists as a script rather than only as a workflow because a local
loop and a workflow file drift apart, and this repository's promise is about
the *local* run. `.github/workflows/ci.yml` is a thin shell that calls the same
file, so the two cannot disagree about what passed.

## Licence

MIT.
