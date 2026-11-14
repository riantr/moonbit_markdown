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

## Using it

The module is published on the registry — [`riantr/moonbit_markdown`](https://mooncakes.io/docs/riantr/moonbit_markdown)
— and the version the tag names is the version that is there:

```
moon add riantr/moonbit_markdown            # the latest release
moon add riantr/moonbit_markdown@0.1.3      # that release exactly
```

The pure packages carry the algorithm and depend on nothing outside this
module, so a project that only renders Markdown to HTML5 needs no other
package. A package whose name begins with a lower case letter is written
with an `@` in front of it, so the renderer reads:

```
import { "riantr/moonbit_markdown/src/md" }

fn main {
  let html = @md.render("# hi")
  println(html)
}
```

The command line tool is the executable in the root of the module, and it is
run from a checkout of it:

```
moon run . mmd2html <in.mmd> out.html
```

## Quick check

Six commands, six one-line verdicts. They need `node` with `puppeteer`
installed (`npm i puppeteer`), `python` with `pypdf`, and a headless Chrome;
nothing else.

```
python ci/ci.py                                # CI PASS: 9/9 steps passed
python ci/ci.py --tiers browser,spec           # the slow half, 4 more steps
moon check                                     # 0 errors, 0 warnings
moon test                                      # 105/105, failed: 0
python verify_pdf_moonbit.py                   # ALL PDF COMPARISON CHECKS PASSED
node verify_page.js moonbit_doubleML_state_diagram.html <in.mmd>
                                               # ALL PAGE CHECKS PASSED
```

`node verify_md_page.js md_with_diagram.html` checks the Markdown side and
prints `MD PAGE CHECKS PASSED`.

The two documents are large — the page runs to about 6 MB and the PDF to
about 6 MB, because the mermaid runtime is inlined and the PDF carries
117 pages. The exact sizes follow the mermaid release that is inlined, so
they are given as figures of speech, not as facts a build can be checked
against. The scripts above read them for you and print a verdict; there is
no need to open either one to check the work.

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
| `src/mdcli` | the command line tool | the pure packages; `moonbitlang/core/async` on `native` and `wasm` |

The four pure packages have no dependencies and build for `native`, `js`,
`wasm` and `wasm-gc` alike, so the same code can render Markdown to HTML5 in a
browser.

### The four targets

The command line tool builds and runs on all four targets too, and the whole
module — the pure packages, the tool and the executable in the root — is
verified on each of them by `ci/check_targets.py`: it builds every target from
scratch, looks for the artefact, starts it, and runs the test suite.

What differs between the targets is the file and process layer underneath the
tool, which is one file per target in `src/mdcli`:

| target | the file and process layer |
| --- | --- |
| `native` | the file system and the process runtime of the toolchain, driven to completion from a synchronous caller |
| `wasm` | the same |
| `js` | Node's own `fs` and `child_process` |
| `wasm-gc` | the file system bridge of the wasm host |

The tool itself is synchronous on every target, so there is one implementation
of it rather than one per target. That is not a small thing: `wasm-gc` has no
async runtime at all, so an `async fn main` cannot even be linked there, and a
tool written in the shape of the other three would not reach it.

One thing `wasm-gc` cannot do is start another program: its host offers no
process module. The commands that drive a browser — `print2pdf`, `md2pdf`,
`mmd2pdf` and `mmd2measure` — therefore report that and produce nothing
there, with a non-zero exit code. Everything else, `md2html` and `mmd2html`
included, works on all four.

The async runtime is the one the toolchain carries, `moonbitlang/core/async`,
not a package that is downloaded from the registry. The module therefore
depends on nothing at all: `moon tree` reports no dependencies, and there is
no version to pin and no version to upgrade. The package that imports it
acknowledges that the toolchain marks it as experimental, with
`options("allow-experimental-packages": true)`.

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
its own margins), `--figures-one-page` (give every diagram a page of its own),
`--figure-page-fit <pt>` and `--figure-page-max <paper>` (give every diagram a
sheet sized to it; see below).

Both paths have a default, and the defaults are the ones on the machine this
was written on — Chrome under `C:\Program Files`, the runtime inside the
mermaid-cli npm package. On another machine, pass the two options. A path that
does not exist is reported, not silently replaced by the default.

The browser is a rasteriser here, not part of the algorithm: the page is
already laid out, and Chrome only turns it into PDF pages.

Both kinds of document print as A4 portrait with 12 mm margins. The Mermaid
runtime is a few megabytes, so a Markdown page only carries it when the
document actually holds a diagram; a document without one stays a couple of
kilobytes.

### Putting each figure on its own page

`--figures-one-page` answers two requests with one switch, because on paper
they are the same request: no drawing is to be broken across a sheet boundary.

On the Markdown side the flag adds a print media block that pushes a page break
before and after every diagram and shrinks the drawing into the height of one
sheet, so a long document keeps its prose paginated as before and each figure
gets a whole page in the middle of it. With a single diagram in the document,
that page is the whole document.

On the scan side the flag replaces the sliced report with a single page: the
whole scan is drawn once and the browser scales it to fit, so a 221 file scan
that normally prints as 117 pages comes out as one. The appendices are not
printed in this mode — the page is the drawing.

The trade is real and stated rather than hidden. A scan drawing is about 9:1,
so on a portrait sheet it becomes a wide band and its labels shrink with it:
the 221 file scan prints its node labels at 0.48 pt. The page shows the shape
of the whole scan and does not pretend to be readable at that size. When the
text has to be legible, the sliced default is the layout that is meant for it.

### Sizing each figure page to its figure

A4 is a fair sheet for prose and a poor one for a drawing: one size for
everything either wastes the small figures or shrinks the large ones past
reading. `--figure-page-fit <pt>` gives each diagram a sheet of its own, sized
so that the labels inside the drawing print at `<pt>` points, and
`--figure-page-max` says how far that may go (default `A2`; `A6` to `A0`, or
`<w>x<h>mm` for a size no paper has).

The PDF format allows it — a page's size is its own MediaBox — and so does this
pipeline, because the paper comes from the page's `@page` rules and CSS named
pages give one rule per figure. No printing the document twice and stitching
the results together.

The size is derived from the drawing rather than from a table of papers. Before
printing, the document's diagrams are rendered once and measured (the same
round trip `mmd2measure` uses); each measured size, with the label size the
browser reports for it, gives the scale that lands those labels on the target.
Text pages keep the A4 they had. Measured on one report — LunaFlow's analysis
of this module, eight diagrams:

```
figure 0   166.2 x 210.0 mm   labels 6.0 pt
figure 2   342.9 x 594.0 mm   labels 3.6 pt   capped by --figure-page-max
figure 3   311.7 x 594.0 mm   labels 4.6 pt   capped by --figure-page-max
figure 4   344.6 x 594.0 mm   labels 5.8 pt   capped by --figure-page-max
figure 6   289.7 x 576.2 mm   labels 6.0 pt
figure 7   148.0 x 371.0 mm   labels 6.0 pt
```

Those six sheets came out of 70 pages; the other 64 stayed A4.

What the tool prints per figure is what the sheet forces, not what was asked
for, and on a page that holds nothing but the drawing the two agree exactly.
Measured on the report above, with the drawings alone in a document, each
figure printed at the size the layout computed:

```
figure 0   166.1 x 209.9 mm   6.17 pt
figure 2   342.9 x 594.1 mm   3.56 pt
figure 3   311.8 x 594.1 mm   4.55 pt
figure 4   344.7 x 576.1 mm   5.82 pt
figure 6   289.6 x 576.1 mm   6.00 pt
figure 7   148.2 x 371.1 mm   6.00 pt
```

In the report as it is - drawings among the text - the same figures print
smaller: 6.17, 3.11, 3.97, 5.08, 5.24, 5.24. The cause is in the browser, and
it is worth stating because it is not a property of the drawing.

A named page runs from the element that names it until another element names a
different one, so the text that follows a drawing lands on the drawing's
sheet. A sheet whose content is taller than its printable area is scaled down
to fit - and the drawing goes down with it. Each figure sheet here is drawn to
the last millimetre of its printable area, so whatever text follows it pushes
it over. The shortfall is not one number but one per figure: against the size
asked for, the six sheets give 1.000, 0.863, 0.863, 0.876, 0.873 and 0.873.
The first figure is the exception and the proof - the drawing after it is one
that failed to render, so almost no text follows it, its sheet does not
overflow, and it prints at full size.

Nothing about the drawing is at fault, and no amount of re-measuring the
drawing will change this: giving the drawing an explicit size, dropping the
bounds, turning the box from a flex container into a plain block, putting the
break on an outer block, moving the text before the drawings, giving the text
its own named sheet, and making the sheets taller or wider were all tried, and
all of them left the shortfall exactly where it was.

So the figure page mode is exact on a sheet that holds one drawing, and short
by 6 to 14 % on a sheet that shares it with text. Two ways out, both known:
print the drawings on their own and put them back into the document, or give
the sheets enough height for the text that lands on them. The second needs a
sheet taller than A2 for the drawings in this report, which is the whole point
of the cap.

Raising the target does not lift the figures the cap binds. Three sheets in that
report are as tall as A2 allows, so 6 pt and 7 pt give them the same 3.11, 3.97
and 5.08 pt; a larger target only widens their sheets. Those three want a taller
cap, or landscape, rather than a larger number.

Two browser behaviours cost the most time here and are worth knowing before
changing this code: a named page is honoured only while the figure fits inside
it, so a box the exact size of the printable area silently falls back to A4 and
the drawing breaks across two sheets; and the per-figure block must not be
stacked on the uniform-A4 one, whose fixed 265 mm height is exactly what stops
the drawing from taking the sheet it was given.

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

**Exit codes:** a command that could not do what it was asked for prints an
`ERROR` line and exits 1; a command that did what it was asked for exits 0. The
usage text, printed when the arguments do not name a command, still exits 0: it
is not a failure, it is the answer to a question nobody asked.

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

**635 of the 652 examples agree (97.4 %).** The sections that agree completely:
thematic breaks, ATX headings, indented and fenced code, HTML blocks, paragraphs,
blank lines, block quotes, list items, inlines, code spans, emphasis and strong
emphasis, images, autolinks, raw HTML, backslash escapes, the HTML5 character
references, precedence, hard and soft line breaks, and the textual content.

What is left is stated rather than hidden:

| section | | |
| --- | --- | --- |
| links | 81/90 | the cases where the text of a link holds an unfinished HTML tag |
| lists | 22/26 | a list whose item holds a nested list with a blank line inside it is called loose when the spec calls it tight |
| tabs | 9/11 | the tab stops inside a list item are counted in columns, not in tab stops |
| setext headings, link reference definitions | 26/27 each | one case each: a label that differs from its reference only in Greek capitals is not folded, because the case folding of the toolchain covers ASCII only |

The report of the script lists the examples that differ, section by section,
which is the honest measure of what is left.

## Tests

```
moon test            # the whole module
moon test src/md     # one package
python ci/check_fmt.py   # the sources are formatted the way `moon fmt` formats them
python ci/check_targets.py   # every target builds, starts and passes its tests
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

The two PDFs have to be built with the **same** mermaid runtime. The numbers
in them come from the browser measuring the drawing, and the measurement
depends on the runtime that drew it: the same runtime gives both PDFs the
same geometry, and a different one gives the reference a different key map
from the MoonBit PDF. `MERMAID_JS` names the runtime for both, and
`verify_pdf_moonbit.py` compares the geometry as well as the text, so a
mismatch is a failure rather than a difference nobody notices.

The browser scripts need puppeteer, which is not a dependency of this module
and is not pinned: `npm i puppeteer` puts a copy in `node_modules/`, and
`env.js` looks there first. Its browser download is not needed — `CHROME`
names the browser to drive, and the usual install locations are tried when
it is not set.

Deleting these files loses nothing but bytes: they are build products, and
`ci/check_artifacts.py` checks their structure against the source they were
generated from.

| document | files | notice states | notes | findings |
| --- | --- | --- | --- | --- |
| `moonbit_doubleML_state_diagram.html` | 221 | 2147 | 2371 | 1 |

The four numbers are the ones the document states about itself, and
`ci/check_artifacts.py` re-derives every one of them from the tracked `.mmd`
source: the page has to agree with the source, and the source has to agree
with this table. No document is compared by its bytes — the mermaid runtime
is inlined in it, the runtime is not pinned to a release, and a page built
with a different mermaid release is just as correct as this one.

The print page is not in the table because it is written by the same command
as the PDF, which needs a browser. The gates tier must run without one, so
the table names only the documents that need nothing but this repository.
`ci/check_artifacts.py` still checks the print page when it is on disk.

The PDFs are not checked at all: Chrome writes a timestamp into every one of
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
- **A tag only moves its final component**: `v0.1.0` → `v0.1.1` → `v0.1.2` → `v0.1.3`.
- **Gitee may be pushed at any time; GitHub only from a green run that has a
  tag**, so what is published there is always a named, tested state.

```
python ci/ci.py --self-check                    # 29/29: the engine's own accounting
python ci/ci.py                                 # env + build + gates (fast, portable)
python ci/ci.py --tiers env,build,gates,browser,spec --check-release
                                                # would a tag be allowed? changes nothing
python ci/ci.py --tiers env,build,gates,browser,spec --tag --push
```

| tier | what it runs | needs |
| --- | --- | --- |
| `env` | `moon`, `node`, `python` versions | nothing |
| `build` | `moon check`, `moon test`, `ci/check_fmt.py`: the source formatting check, the four pure packages on all four targets, `ci/check_targets.py`: every target builds, starts and passes its tests | nothing |
| `gates` | `ci/check_artifacts.py`: the structure of the generated documents | the generated documents |
| `browser` | `verify_page.js`, `verify_md_page.js`, `verify_pdf_moonbit.py` | Chrome, the generated documents |
| `spec` | `tools/commonmark_spec.js`, against the floor this README states | the spec download |

The default run is `env,build,gates` because it is portable — no browser, no
network — and it is what a tag is normally granted from. The two opt-in tiers
are slow, and when they are left out the tag gate **names them** rather than
silently dropping them: a green that quietly ignored the browser checks is not
green. A full release points at all five.

### The publish

The tag is not the last step: it is what starts the release.

| remote | what it carries |
| --- | --- |
| gitee | the working remote: the commits and the tags |
| GitHub | the release remote: the tag push starts the publish |

`.github/workflows/publish.yml` runs on a `v*` tag pushed to GitHub. It checks
the tag out, refuses it unless the tag's version and `moon.mod`'s version are
the same number, runs the same `ci/ci.py` engine the local run uses, publishes
to the registry, and creates the GitHub Release. Its gate is `env,build`: the
other tiers need the generated documents, a browser, or a spec download that
only works on Windows, so they are verified locally instead.

The publish needs the registry token. The workflow reads it from the
repository secret `MOONCAKES_RIANTR_TOKEN`, and that secret holds the JSON
body of `~/.moon/credentials.json` — an object with a `token` and a
`username` — not a bare token. The workflow checks the shape and says so,
because the alternative is an authentication error that says nothing. A file
written by Windows PowerShell carries a byte-order mark, and a secret copied
out of such a file carries it too; the workflow removes one and says that it
did, because a file with a mark on the front is not JSON.

The publish is never done by hand. `moon publish` on a version that already
exists fails, and the registry's `latest` means "whatever was published
last", so a manual publish would leave the registry pointing somewhere the
tag order does not suggest.

The engine exists as a script rather than only as a workflow because a local
loop and a workflow file drift apart, and this repository's promise is about
the *local* run. `.github/workflows/ci.yml` is a thin shell that calls the same
file, so the two cannot disagree about what passed.

## Licence

MIT.
