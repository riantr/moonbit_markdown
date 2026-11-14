///|
/// The command line tool.
///
/// Subcommands:
///   md2html <in.md> <out.html>              Markdown to a self-contained page
///   mmd2html <in.mmd> <out.html>            a Mermaid scan to the page
///   print2pdf <in.html> <out.pdf>           an HTML page to PDF, via Chrome
///   md2pdf <in.md> <out.pdf>                Markdown to PDF in one step
///   mmd2pdf <in.mmd> <out.pdf>              a Mermaid scan to PDF in one step
///   mmd2measure <in.mmd>                    the measured geometry of a scan
///
/// Options:
///   --mermaid-js <path>   the mermaid runtime to inline (default: the copy
///                          inside the mermaid-cli npm package, looked for
///                          through MERMAID_JS and the npm roots)
///   --chrome <path>       the Chrome/Edge binary to drive for PDF output
///   --header-footer       let the browser print its own header and footer
///                          (off by default: the document has its own margins)
///   --figures-one-page    one diagram, one page: the drawing gets a page to
///                          itself and is scaled down until it fits, instead
///                          of being broken across two sheets (off by default)
///   --figure-page-fit <pt> one diagram, one page, sized to the diagram: each
///                          figure page is a sheet big enough for the labels
///                          inside the drawing to print at <pt> (implies
///                          --figures-one-page)
///   --figure-page-max <p>  the largest sheet --figure-page-fit may ask for:
///                          A6..A0, or <w>x<h>mm (default: A2)
///
/// The figure-page flags exist because a PDF is read, while the Markdown it
/// came from is parsed: one paper size for the whole document forces a choice
/// between wasting the small drawings and shrinking the large ones past
/// reading. Splitting the difference per page is what CSS named pages are for,
/// and the size a drawing needs is measured from the drawing itself.
///
/// NOTE ON EXIT CODES: a command that could not produce what it was
/// asked for exits non-zero. The messages are the same ones as before -
/// what a caller can rely on now is the exit code, so a CI step does not
/// have to read the output to know whether the page was written.

///|
/// The mermaid runtime the author used.
///
/// It is the last fallback of the lookup: the npm roots are tried first,
/// and this copy is what is left when none of them has one. It is kept
/// because it is the copy on the machine the tool was written on, and
/// that machine must keep working.
const DEFAULT_MERMAID_JS : String = "C:\\Users\\hp\\AppData\\Roaming\\npm\\node_modules\\@mermaid-js\\mermaid-cli\\node_modules\\mermaid\\dist\\mermaid.min.js"

///|
const DEFAULT_CHROME : String = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"

///|
/// The largest sheet the figure-page mode may ask for.
const DEFAULT_FIGURE_PAGE_MAX : String = "A2"

///|
/// The smallest sheet the figure-page mode may ask for: below this the page
/// reads as a mistake rather than as a page.
const FIGURE_PAGE_MIN : String = "A5"

///|
fn usage() -> Unit {
  println("riantr/moonbit_markdown")
  println("")
  println(
    "  md2html <in.md> <out.html>              Markdown to a self-contained page",
  )
  println(
    "  mmd2html <in.mmd> <out.html>            a Mermaid scan to the page",
  )
  println(
    "  print2pdf <in.html> <out.pdf>           an HTML page to PDF, via Chrome",
  )
  println(
    "  md2pdf <in.md> <out.pdf>                Markdown to PDF in one step",
  )
  println(
    "  mmd2pdf <in.mmd> <out.pdf>              a Mermaid scan to PDF in one step",
  )
  println(
    "  mmd2measure <in.mmd>                    the measured geometry of a scan",
  )
  println("")
  println("  --mermaid-js <path>    the mermaid runtime to inline")
  println("  --chrome <path>        the Chrome binary to drive for PDF output")
  println(
    "  --header-footer        let the browser print its own header and footer",
  )
  println(
    "  --figures-one-page     give each diagram a page of its own, scaled to fit",
  )
  println(
    "  --figure-page-fit <pt> give each diagram a sheet sized to it, so its",
  )
  println(
    "                         labels print at <pt> (default when used: 6)",
  )
  println(
    "  --figure-page-max <p>  the largest sheet to ask for: A6..A0 or WxHmm",
  )
  println("                         (default: A2)")
}

///|
/// The mermaid runtime: where it is looked for, and in what order.
///
/// The order is the one the Python tool in this repository uses, so the
/// two find the runtime in the same places:
///
///   1. the MERMAID_JS variable, if it is set - and it has to be there,
///      because a variable that names nothing is an error and not a hint
///      to look further;
///   2. the npm roots: $NPM_CONFIG_PREFIX, and then the roots the
///      platform puts a global install in;
///   3. the author's own copy, as the last fallback.
///
/// Under each root two names are tried: the runtime inside the
/// mermaid-cli package, and the one in a plain mermaid install.
///

///|
/// The value of a variable, or None when it is not set or is empty.
///
/// An empty variable says nothing, so it is the same as a variable that
/// is not there at all.
///
fn env_of(env : Map[String, String], key : String) -> String? {
  match env.get(key) {
    Some(v) => if v.is_empty() { None } else { Some(v) }
    None => None
  }
}

///|
/// Whether this is Windows.
///
/// `OS` is the variable Windows itself sets, and `APPDATA` is one only
/// Windows has: either of them says Windows, and neither is set on the
/// other systems.
///
fn is_windows(env : Map[String, String]) -> Bool {
  match env_of(env, "OS") {
    Some(os) => os == "Windows_NT"
    None =>
      match env_of(env, "APPDATA") {
        Some(_) => true
        None => false
      }
  }
}

///|
/// The separator the paths of this system are written with.
///
fn path_sep(env : Map[String, String]) -> String {
  if is_windows(env) {
    "\\"
  } else {
    "/"
  }
}

///|
/// The paths the mermaid runtime may be at, in the order they are tried.
///
/// The npm roots come first - that is where a global install puts it -
/// and the two names the package can have are tried under each of them.
///
/// Pure: the environment decides, and nothing else does.
///
fn mermaid_js_candidates(env : Map[String, String]) -> Array[String] {
  let sep = path_sep(env)
  let roots : Array[String] = []
  match env_of(env, "NPM_CONFIG_PREFIX") {
    Some(p) => roots.push(p + sep + "lib" + sep + "node_modules")
    None => ()
  }
  if is_windows(env) {
    match env_of(env, "APPDATA") {
      Some(p) => roots.push(p + sep + "npm" + sep + "node_modules")
      None => ()
    }
    match env_of(env, "ProgramData") {
      Some(p) => roots.push(p + sep + "npm" + sep + "node_modules")
      None => ()
    }
  } else {
    roots.push("/usr/local/lib/node_modules")
    roots.push("/usr/lib/node_modules")
    match env_of(env, "HOME") {
      Some(h) => {
        roots.push(h + sep + ".npm-global" + sep + "lib" + sep + "node_modules")
        roots.push(h + sep + ".local" + sep + "lib" + sep + "node_modules")
      }
      None => ()
    }
  }
  let cli = "@mermaid-js" +
    sep +
    "mermaid-cli" +
    sep +
    "node_modules" +
    sep +
    "mermaid" +
    sep +
    "dist" +
    sep +
    "mermaid.min.js"
  let plain = "mermaid" + sep + "dist" + sep + "mermaid.min.js"
  let out : Array[String] = []
  for r in roots {
    out.push(r + sep + cli)
    out.push(r + sep + plain)
  }
  out
}

///|
/// The mermaid runtime to inline: the path to it, or None when there is
/// none.
///
/// The order is the one above: the MERMAID_JS variable first, then the
/// npm roots.
///
/// Pure: the environment and the test for whether a path is there are the
/// only inputs, so the order can be checked without a filesystem.
///
fn find_mermaid_js(
  env : Map[String, String],
  exists : (String) -> Bool,
) -> String? {
  match env_of(env, "MERMAID_JS") {
    Some(p) => if exists(p) { Some(p) } else { None }
    None => {
      for c in mermaid_js_candidates(env) {
        if exists(c) {
          return Some(c)
        }
      }
      None
    }
  }
}

///|
/// The mermaid runtime to inline: the path to read.
///
/// The lookup finds it, and the author's own copy is the last fallback:
/// the machine the tool was written on keeps working when the lookup
/// finds nothing. A variable that names a file that is not there is
/// reported as itself, because that is the file the caller has to fix.
///
fn mermaid_js_path() -> String {
  let env = @env.get_env_vars()
  let named = env_of(env, "MERMAID_JS")
  // the paths that are there, so that the lookup itself stays pure. The
  // file system is asked once: the candidates are looked for as a list,
  // because asking the file system about each of them in turn is asking it
  // about the same place several times over.
  let there : Array[String] = []
  match io_first_existing(mermaid_js_candidates(env)) {
    Some(p) => there.push(p)
    None => ()
  }
  match named {
    Some(p) => if io_exists(p) { there.push(p) }
    None => ()
  }
  let exists = fn(p : String) -> Bool { there.contains(p) }
  match find_mermaid_js(env, exists) {
    Some(p) => p
    None =>
      match named {
        Some(p) => p
        None => DEFAULT_MERMAID_JS
      }
  }
}

///|
/// The argument index of the first user argument.
///
/// The offset is not the same on every target: the js backend runs under
/// node, and node's own arguments come first. The offset each target has is
/// in the file that belongs to it - argv_native.mbt and argv_js.mbt.
///

///|
fn read_text(path : String) -> String? {
  match io_read_text(path) {
    Some(t) => Some(t)
    None => {
      // the file system is asked whether the file is there only now: on the
      // happy path the read has already answered the question
      if io_exists(path) {
        println("ERROR\tcannot read \{path}")
      } else {
        println("ERROR\tno such file: \{path}")
      }
      None
    }
  }
}

///|
/// Write a file, and say that it was written.
///
/// The write is checked: a path that cannot be written to is a failure,
/// and a failure has to show in the exit code as well - a page that was
/// never written must not be reported as one that was.
///
fn write_text(path : String, content : String) -> Bool {
  if !io_write_text(path, content) {
    println("ERROR\tcannot write \{path}")
    return false
  }
  println("wrote \{path} (\{(content.length() / 1024)} KB)")
  true
}

///|
/// The mermaid runtime to inline, read from where it is.
///
/// The path is resolved only when the runtime is needed: a document
/// without a diagram never needs it, so a missing runtime must not stop
/// such a document from being written.
///
fn read_mermaid_js(named : String?) -> String? {
  match named {
    Some(p) => read_text(p)
    None => read_text(mermaid_js_path())
  }
}

///|
/// The document title of an HTML page, taken from its file name.
///
fn file_title(path : String) -> String {
  let cs = @text.chars(path)
  let mut start = 0
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '/' || cs[i] == '\\' {
      start = i + 1
    }
    i += 1
  }
  let mut dot = -1
  let mut i = start
  while i < cs.length() {
    if cs[i] == '.' {
      dot = i
    }
    i += 1
  }
  if dot > start {
    @text.text(cs, start, dot)
  } else {
    @text.text(cs, start, cs.length())
  }
}

///|
/// Build the HTML5 page for a Mermaid scan.
///
fn mmd_to_html(
  in_path : String,
  out_path : String,
  mermaid_js : String?,
) -> Bool {
  match read_text(in_path) {
    Some(src) => {
      let d = @mermaid.parse_diagram(src)
      println(
        "parsed \{d.files.length()} files, \{@mermaid.drawn_notices(d)} notice states, \{@mermaid.drawn_findings(d)} findings",
      )
      let runtime = match read_mermaid_js(mermaid_js) {
        Some(js) => js
        None => {
          // the scan page IS a Mermaid application: the client script draws
          // the overview, the sidebar and every sub-diagram. Without the
          // runtime there is nothing to show, so nothing is written - the same
          // rule the measure and print steps already follow.
          println(
            "ERROR\tcannot inline the mermaid runtime; the page cannot draw the diagram, so no page was written",
          )
          return false
        }
      }
      let title = @mermaid.meta_of(d, "target") +
        " — Mermaid state diagram (HTML5 render)"
      let page = @mermaid.render_page(d, runtime, title, src)
      write_text(out_path, page)
    }
    None => false
  }
}

///|
/// Build the HTML5 page for a Markdown document.
///
/// The mermaid runtime is 2.6 MB, so it is only inlined when the document
/// actually holds a diagram: a page without one stays a page without it.
///

///|
/// A document, ready to be written as a page: its blocks (which the figure
/// measurement walks), its rendered body, and the runtime that draws it.
priv struct RenderedDoc {
  blocks : Array[@md.Block]
  body : String
  mermaid_js : String
}

///|
/// Parse and render the document, or report why it cannot be drawn.
///
/// `md2html` and `md2pdf` both need exactly this, and a document whose diagram
/// cannot be drawn has to fail the same way through either, so the first half
/// of both lives here.
fn render_document(in_path : String, mermaid_js : String?) -> RenderedDoc? {
  match read_text(in_path) {
    Some(src) => {
      let blocks = @md.parse_document(src)
      let body = @md.render_blocks(blocks)
      let runtime = if @md.needs_runtime(blocks) {
        match read_mermaid_js(mermaid_js) {
          Some(js) => js
          None => {
            // the document holds a diagram, so it needs the runtime; a page
            // whose diagram would only show its source is not worth writing
            println(
              "ERROR\tcannot inline the mermaid runtime; the diagram cannot be drawn, so no page was written",
            )
            return None
          }
        }
      } else {
        ""
      }
      Some({ blocks, body, mermaid_js: runtime, })
    }
    None => None
  }
}

///|
fn md_to_html(
  in_path : String,
  out_path : String,
  mermaid_js : String?,
  figures_one_page : Bool,
) -> Bool {
  match render_document(in_path, mermaid_js) {
    Some(doc) => {
      let page = @md.render_page(
        file_title(in_path),
        doc.body,
        doc.mermaid_js,
        figures_one_page~,
      )
      write_text(out_path, page)
    }
    None => false
  }
}

///|
/// Lay out one sheet per drawing, and return the stylesheet fragment that
/// hands them out.
///
/// The measurement is a round trip through the browser because a drawing's
/// size is only known once the drawing exists; the arithmetic that turns those
/// sizes into sheets is `@md.figure_pages`. The result is reported per figure
/// on purpose: when `--figure-page-max` bites, the labels land below the
/// target, and a silent degradation is the one thing this mode must not do.
fn figure_page_sheets(
  doc : RenderedDoc,
  chrome : String,
  target_pt : Double,
  max_spec : String,
) -> String? {
  let sources = @md.mermaid_sources(doc.blocks)
  if sources.is_empty() {
    println(
      "NOTE\tthis document holds no diagram, so the page size is unchanged",
    )
    return Some("")
  }
  let max_mm = match @md.paper_of(max_spec) {
    Some(p) => p
    None => {
      println("ERROR\tunknown paper size for --figure-page-max: " + max_spec)
      return None
    }
  }
  let min_mm = match @md.paper_of(FIGURE_PAGE_MIN) {
    Some(p) => p
    None => (148.0, 210.0)
  }
  let measure_path = "measure.html"
  if !io_write_text(
      measure_path,
      @printpdf.measure_page(sources, doc.mermaid_js),
    ) {
    println("ERROR\tcannot write \{measure_path}")
    return None
  }
  let dom = match dump_dom(chrome, measure_path) {
    Some(x) => x
    None => {
      println("ERROR\tthe browser did not return the measurement")
      ignore(io_remove(measure_path))
      return None
    }
  }
  ignore(io_remove(measure_path))
  let m = @printpdf.parse_measurement(dom)
  for e in m.errors {
    println("ERROR\ta diagram did not render: " + e)
  }
  let pages = @md.figure_pages(
    m.dims,
    m.fonts,
    target_pt,
    max_mm,
    min_mm,
    @md.FIGURE_MARGIN_MM,
  )
  for p in pages {
    let mut line = "figure " +
      p.index.to_string() +
      "\t" +
      @printpdf.fmt1(p.width_mm) +
      " x " +
      @printpdf.fmt1(p.height_mm) +
      " mm\tlabels " +
      @printpdf.fmt1(p.label_pt) +
      " pt"
    if p.capped {
      line = line + "\tcapped by --figure-page-max"
    }
    println(line)
  }
  Some(@md.figure_page_css(pages, @md.FIGURE_MARGIN_MM))
}

///|
/// Render a Markdown document to PDF, optionally with a sheet per figure.
///
/// With a figure target the document is laid out twice: once so the browser
/// can measure the drawings, once with the sheets those measurements imply.
/// Nothing in the second pass is guessed - the first pass is what makes the
/// second possible.
fn md_to_pdf(
  in_path : String,
  out_path : String,
  mermaid_js : String?,
  chrome : String,
  header_footer : Bool,
  figures_one_page : Bool,
  figure_fit_pt : Double?,
  figure_max : String,
) -> Bool {
  match render_document(in_path, mermaid_js) {
    Some(doc) => {
      let mut extra_css = ""
      let mut one_page = figures_one_page
      match figure_fit_pt {
        None => ()
        Some(pt) =>
          match figure_page_sheets(doc, chrome, pt, figure_max) {
            Some(css) => {
              // a sheet per figure is a page per figure, so this mode implies
              // the one-page layout rather than stacking two layouts
              one_page = true
              extra_css = css
            }
            None => return false
          }
      }
      let page = @md.render_page(
        file_title(in_path),
        doc.body,
        doc.mermaid_js,
        figures_one_page=one_page,
        extra_print_css=extra_css,
      )
      let tmp = sidecar_path(out_path, ".html")
      if !write_text(tmp, page) {
        return false
      }
      print_pdf(tmp, out_path, chrome, header_footer)
    }
    None => false
  }
}

///|
/// Print a laid-out page to a PDF, and say whether the PDF was written.
///
/// The browser reports its own failures, but a file that is not there is
/// a run that produced nothing - and a run that produced nothing must
/// not look like a run that did.
///
fn print_pdf(
  in_path : String,
  out_path : String,
  chrome : String,
  header_footer : Bool,
) -> Bool {
  let browser = io_exists(chrome)
  print_to_pdf(in_path, out_path, chrome, header_footer)
  browser && io_exists(out_path)
}

///|
/// Measure a Mermaid scan's detail drawing and report the geometry.
///
/// This is the first half of the print chain, on its own: it renders the
/// actionable file's drawing in the browser, reads the geometry of every
/// node back, and prints it. It is how the print layout gets the numbers it
/// needs - and how those numbers can be checked against the drawing.
///
fn mmd_to_measure(
  in_path : String,
  mermaid_js : String?,
  chrome : String,
) -> Bool {
  match read_text(in_path) {
    Some(src) => {
      let d = @mermaid.parse_diagram(src)
      let p = @printpdf.plan(d)
      let runtime = match read_mermaid_js(mermaid_js) {
        Some(js) => js
        None => {
          println("ERROR\tcannot inline the mermaid runtime")
          return false
        }
      }
      let measure_path = "measure.html"
      if !io_write_text(
          measure_path,
          @printpdf.measure_page([p.detail_full, p.detail_focus], runtime),
        ) {
        println("ERROR\tcannot write \{measure_path}")
        return false
      }
      let dom = match dump_dom(chrome, measure_path) {
        Some(x) => x
        None => {
          println("ERROR\tthe browser did not return the measurement")
          // the measurement page is a temporary file: it is removed when the
          // command is done with it, and a run that failed is done with it
          // too
          ignore(io_remove(measure_path))
          return false
        }
      }
      let m = @printpdf.parse_measurement(dom)
      let (w, h) = @printpdf.full_size(m)
      let (fw, fh) = @printpdf.focus_size(m)
      println(
        "full:   \{@printpdf.fmt0(w)} x \{@printpdf.fmt0(h)} px in \{m.nodes.length()} nodes",
      )
      println("focused: \{@printpdf.fmt0(fw)} x \{@printpdf.fmt0(fh)} px")
      for e in m.errors {
        println("ERROR\t\{e}")
      }
      for n in m.nodes {
        println(
          "node\t\{n.id}\t\{@printpdf.fmt0(n.x)}\t\{@printpdf.fmt0(n.y)}\t\{@printpdf.fmt0(n.w)}\t\{@printpdf.fmt0(n.h)}",
        )
      }
      let cls = @printpdf.classify(m.nodes, p.detail_id)
      println(
        "chain  \{@printpdf.fmt0(cls.chain.from)}-\{@printpdf.fmt0(cls.chain.to)}",
      )
      println(
        "states \{@printpdf.fmt0(cls.states.from)}-\{@printpdf.fmt0(cls.states.to)} (\{cls.states_n})",
      )
      println(
        "boiler \{@printpdf.fmt0(cls.boiler.from)}-\{@printpdf.fmt0(cls.boiler.to)} (\{cls.boiler_n})",
      )
      println(
        "defect \{@printpdf.fmt0(cls.defect.from)}-\{@printpdf.fmt0(cls.defect.to)}",
      )
      println(
        "why    \{@printpdf.fmt0(cls.why.from)}-\{@printpdf.fmt0(cls.why.to)}",
      )
      ignore(io_remove(measure_path))
      true
    }
    None => false
  }
}

///|
/// The path of a sidecar file next to the output.
///
/// `out.pdf` becomes `out.print.html` and `out.measure.html`, so the two
/// intermediate pages can be looked at, or printed again, next to the
/// document they produced.
///
fn sidecar_path(out_path : String, suffix : String) -> String {
  let cs = @text.chars(out_path)
  let mut dot = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '.' {
      dot = i
    }
    i += 1
  }
  if dot > 0 {
    out_path[0:dot].to_owned() + suffix
  } else {
    out_path + suffix
  }
}

///|
/// Print a Mermaid scan as a paginated PDF.
///
/// The chain has three steps, and the algorithm is in the middle one:
///
///   1. the browser renders the actionable file's diagram and reports the
///      geometry of every node in it;
///   2. MoonBit reads that geometry back and lays out the document: the
///      cover, the overview slices, the key map with its tick marks, the
///      enlarged finding, the notice list and the two appendices;
///   3. the browser renders the sheets that MoonBit laid out and prints them
///      to PDF.
///
/// Nothing in the layout is left to the browser, and nothing is left to the
/// PDF: the notice count in the appendix is the notice count of the source.
///
fn mmd_to_pdf(
  in_path : String,
  out_path : String,
  mermaid_js : String?,
  chrome : String,
  header_footer : Bool,
  figures_one_page : Bool,
) -> Bool {
  match read_text(in_path) {
    Some(src) => {
      let d = @mermaid.parse_diagram(src)
      println(
        "parsed \{d.files.length()} files, \{@mermaid.drawn_notices(d)} notice states, \{@mermaid.drawn_findings(d)} findings",
      )
      let runtime = match read_mermaid_js(mermaid_js) {
        Some(js) => js
        None => {
          println("ERROR\tcannot inline the mermaid runtime")
          return false
        }
      }
      let p = @printpdf.plan(d)
      if figures_one_page {
        // the whole drawing on one sheet: there is nothing to measure and
        // nothing to slice, so the report geometry has no say here
        let print_path = sidecar_path(out_path, ".print.html")
        if !io_write_text(print_path, @printpdf.print_one_page(d, runtime)) {
          println("ERROR\tcannot write \{print_path}")
          return false
        }
        println("wrote \{print_path} (\{io_file_size(print_path) / 1024} KB)")
        return print_pdf(print_path, out_path, chrome, header_footer)
      }
      if p.detail_index < 0 {
        println(
          "ERROR\tthis scan has no file with an actionable finding, so there is no detail section",
        )
      }
      // ---- step 1: measure the detail drawing
      let measure_path = sidecar_path(out_path, ".measure.html")
      let sources = [p.detail_full, p.detail_focus]
      if !io_write_text(measure_path, @printpdf.measure_page(sources, runtime)) {
        println("ERROR\tcannot write \{measure_path}")
        return false
      }
      let dom = match dump_dom(chrome, measure_path) {
        Some(x) => x
        None => {
          println("ERROR\tthe browser did not return the measurement")
          ignore(io_remove(measure_path))
          return false
        }
      }
      let m = @printpdf.parse_measurement(dom)
      if m.dims.is_empty() || m.nodes.is_empty() {
        println(
          "ERROR\tthe browser returned no geometry; the measurement page did not run",
        )
        println(
          "the measurement page is left at \{measure_path} for inspection",
        )
        return false
      }
      if !m.errors.is_empty() {
        for e in m.errors {
          println("ERROR\tmeasure: \{e}")
        }
        ignore(io_remove(measure_path))
        return false
      }
      let (w, h) = @printpdf.full_size(m)
      let (fw, fh) = @printpdf.focus_size(m)
      println(
        "measured the detail drawing: \{@printpdf.fmt0(w)} x \{@printpdf.fmt0(h)} px in \{m.nodes.length()} nodes; the focused drawing: \{@printpdf.fmt0(fw)} x \{@printpdf.fmt0(fh)} px",
      )
      // ---- step 2: lay the document out
      let print_path = sidecar_path(out_path, ".print.html")
      if !io_write_text(print_path, @printpdf.print_document(d, p, m, runtime)) {
        println("ERROR\tcannot write \{print_path}")
        return false
      }
      println("wrote \{print_path} (\{io_file_size(print_path) / 1024} KB)")
      // ---- step 3: print it
      let printed = print_pdf(print_path, out_path, chrome, header_footer)
      ignore(io_remove(measure_path))
      printed
    }
    None => false
  }
}

///|

///|
/// Run the command line tool with the given arguments (argv, argv[0] is the
/// program itself).
///
pub fn run(args : Array[String]) -> Unit {
  let mut i = user_arg_start(args)
  if i >= args.length() {
    usage()
    return
  }
  let cmd = args[i]
  i += 1
  let positional : Array[String] = []
  // None means the runtime is looked for; Some is a path the caller named
  let mut mermaid_js : String? = None
  let mut chrome = DEFAULT_CHROME
  let mut header_footer = false
  let mut figures_one_page = false
  let mut figure_fit_pt : Double? = None
  let mut figure_max = DEFAULT_FIGURE_PAGE_MAX
  while i < args.length() {
    let a = args[i]
    if a == "--mermaid-js" && i + 1 < args.length() {
      i += 1
      mermaid_js = Some(args[i])
    } else if a == "--chrome" && i + 1 < args.length() {
      i += 1
      chrome = args[i]
    } else if a == "--figures-one-page" {
      // one diagram, one page: the drawing is scaled down until it fits,
      // instead of being broken across two sheets
      figures_one_page = true
    } else if a == "--figure-page-fit" && i + 1 < args.length() {
      // one diagram, one sheet, and the sheet is sized to the drawing: this
      // is the mode where the PDF stops pretending every page is A4
      i += 1
      let pt = @printpdf.parse_num(args[i])
      if pt <= 0.0 {
        println("ERROR\t--figure-page-fit needs a size in points, above zero")
      } else {
        figure_fit_pt = Some(pt)
      }
    } else if a == "--figure-page-max" && i + 1 < args.length() {
      i += 1
      figure_max = args[i]
    } else if a == "--header-footer" {
      // the browser's own header and footer are off by default: the document
      // carries its own margins, and the browser's date-and-URL banner would
      // sit on top of them
      header_footer = true
    } else if a == "--no-header-footer" {
      header_footer = false
    } else {
      positional.push(a)
    }
    i += 1
  }
  // whether the command produced what it was asked for
  let mut ok = true
  match cmd {
    "md2html" =>
      if positional.length() < 2 {
        usage()
      } else {
        ok = md_to_html(
          positional[0],
          positional[1],
          mermaid_js,
          figures_one_page,
        )
      }
    "mmd2html" =>
      if positional.length() < 2 {
        usage()
      } else {
        ok = mmd_to_html(positional[0], positional[1], mermaid_js)
      }
    "print2pdf" =>
      if positional.length() < 2 {
        usage()
      } else {
        ok = print_pdf(positional[0], positional[1], chrome, header_footer)
      }
    "md2pdf" =>
      if positional.length() < 2 {
        usage()
      } else {
        ok = md_to_pdf(
          positional[0],
          positional[1],
          mermaid_js,
          chrome,
          header_footer,
          figures_one_page,
          figure_fit_pt,
          figure_max,
        )
      }
    "mmd2measure" =>
      if positional.length() < 1 {
        usage()
      } else {
        ok = mmd_to_measure(positional[0], mermaid_js, chrome)
      }
    "mmd2pdf" =>
      if positional.length() < 2 {
        usage()
      } else {
        ok = mmd_to_pdf(
          positional[0],
          positional[1],
          mermaid_js,
          chrome,
          header_footer,
          figures_one_page,
        )
      }
    _ => usage()
  }
  if !ok {
    // the command could not do what it was asked for: the messages above
    // say why, and the exit code says that it did not happen
    @env.exit(EXIT_FAILURE)
  }
}

///|
/// The exit code of a command that could not do what it was asked for.
///
const EXIT_FAILURE : Int32 = 1
