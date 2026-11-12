///|
/// Building the self-contained HTML5 page for a Mermaid scan.

///|
/// The page renders on the client. Mermaid's layout engine (dagre) cannot
/// lay out the whole scan in one piece: it fails with "Cannot set properties
/// of undefined (setting 'order')" once more than about thirty compound
/// states carry notes, and the drawing would be around 129 MB even if it
/// worked. So the page ships the scan SPLIT into
///
///   - one flat overview graph (no compound nesting), and
///   - one sub-diagram per file, each small enough for dagre to lay out.
///
/// The splitting decision lives here, in MoonBit - it is the algorithm, not
/// the browser's job. The browser only runs mermaid on the pieces it is
/// given.
///
/// Everything the page needs is inlined: the mermaid runtime, the diagram
/// sources and the client script. The result is one file that works from
/// `file://` with no network and no sidecar assets.
///

///|
/// Escape a string for a JSON string literal.
///
/// `/` is escaped as well: the result is embedded in a `<script>` element,
/// and a literal `</script>` inside it would end the element early. As
/// `</` can only occur as `<\/`, escaping the slash removes the hazard
/// without changing the decoded string.
///
pub fn json_escape(s : String) -> String {
  let sb = StringBuilder()
  for c in s.iter() {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '/' => sb.write_string("\\u002f")
      '<' => sb.write_string("\\u003c")
      '>' => sb.write_string("\\u003e")
      '&' => sb.write_string("\\u0026")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// The flat overview graph.
///
/// `direction LR` keeps the files in one tall column instead of a single
/// unreadable 115,010 px row, and it reads top-to-bottom like a list.
///
pub fn overview_source(d : Diagram) -> String {
  let sb = StringBuilder()
  sb.write_string("stateDiagram-v2\n    direction LR\n")
  for f in d.files {
    sb.write_string("    state \"")
    sb.write_string(f.id)
    sb.write_string(" ")
    sb.write_string(EM)
    sb.write_string(" ")
    sb.write_string(f.path)
    sb.write_string("\" as ")
    sb.write_string(f.id)
    sb.write_string("\n")
  }
  sb.write_string("    state \"scan ")
  sb.write_string(EM)
  sb.write_string(" ")
  sb.write_string(meta_of(d, "target"))
  sb.write_string("\" as scan\n")
  for f in d.files {
    sb.write_string("    scan --> ")
    sb.write_string(f.id)
    sb.write_string(" : ")
    sb.write_string(f.actionable.to_string())
    sb.write_string(" actionable, ")
    sb.write_string(f.notice_count.to_string())
    sb.write_string(" notice(s), parsed\n")
  }
  sb.to_string()
}

///|
/// The sub-diagram of one file: the block's own lines, verbatim.
///
pub fn file_source(f : FileBlock) -> String {
  let sb = StringBuilder()
  sb.write_string("stateDiagram-v2\n    direction TB\n")
  for line in f.lines {
    sb.write_string(line)
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// The per-file data the client script needs, as JSON.
///
fn files_json(d : Diagram) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  for i in 0..<d.files.length() {
    let f = d.files[i]
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"id\":")
    sb.write_string("\"")
    sb.write_string(json_escape(f.id))
    sb.write_string("\",\"path\":")
    sb.write_string("\"")
    sb.write_string(json_escape(f.path))
    sb.write_string("\",\"name\":")
    sb.write_string("\"")
    sb.write_string(json_escape(file_name(f)))
    sb.write_string("\",\"actionable\":")
    sb.write_string(f.actionable.to_string())
    sb.write_string(",\"noticeCount\":")
    sb.write_string(f.notice_count.to_string())
    sb.write_string(",\"notices\":[")
    let mut first = true
    for s in f.states {
      if is_notice(s.msg) {
        if !first {
          sb.write_string(",")
        }
        first = false
        sb.write_string("{\"id\":\"")
        sb.write_string(json_escape(s.id))
        sb.write_string("\",\"msg\":")
        sb.write_string("\"")
        sb.write_string(json_escape(s.msg))
        sb.write_string("\"}")
      }
    }
    sb.write_string("],\"findings\":[")
    let mut first = true
    for s in f.states {
      if !is_notice(s.msg) && !is_stage(s.msg) && !is_file_label(f.id, s.msg) {
        if !first {
          sb.write_string(",")
        }
        first = false
        sb.write_string("{\"id\":\"")
        sb.write_string(json_escape(s.id))
        sb.write_string("\",\"msg\":")
        sb.write_string("\"")
        sb.write_string(json_escape(s.msg))
        sb.write_string("\"}")
      }
    }
    sb.write_string("],\"src\":")
    sb.write_string("\"")
    sb.write_string(json_escape(file_source(f)))
    sb.write_string("\"}")
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn file_name(f : FileBlock) -> String {
  let cs = chars(f.path)
  let mut start = 0
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '/' {
      start = i + 1
    }
    i += 1
  }
  f.path[start:f.path.length()].to_owned()
}

///|
/// The metadata block, as JSON.
///
fn meta_json(d : Diagram) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  for i in 0..<d.meta.length() {
    let (k, v) = d.meta[i]
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"")
    sb.write_string(json_escape(k))
    sb.write_string("\":\"")
    sb.write_string(json_escape(v))
    sb.write_string("\"")
  }
  sb.write_string("}")
  sb.to_string()
}

///|
/// The numbers the source claims next to the numbers the source draws. A
/// difference here is a property of the source, and the page says so rather
/// than hiding it.
///
fn counts_json(d : Diagram) -> String {
  let claimed_notices = meta_of(d, "notices")
  let sb = StringBuilder()
  sb.write_string("{\"files\":")
  sb.write_string(d.files.length().to_string())
  sb.write_string(",\"claimedFiles\":")
  sb.write_string("\"" + json_escape(meta_of(d, "files")) + "\"")
  sb.write_string(",\"claimedNotices\":")
  sb.write_string("\"" + json_escape(claimed_notices) + "\"")
  sb.write_string(",\"drawnNotices\":")
  sb.write_string(drawn_notices(d).to_string())
  sb.write_string(",\"drawnStates\":")
  sb.write_string(drawn_states(d).to_string())
  sb.write_string(",\"drawnNotes\":")
  sb.write_string(drawn_notes(d).to_string())
  sb.write_string(",\"drawnFindings\":")
  sb.write_string(drawn_findings(d).to_string())
  sb.write_string(",\"claimedFindings\":")
  sb.write_string("\"" + json_escape(meta_of(d, "actionable")) + "\"")
  sb.write_string("}")
  sb.to_string()
}

///|
/// The number of states the diagram actually draws.
///
pub fn drawn_states(d : Diagram) -> Int32 {
  let mut n = 0
  for f in d.files {
    n += f.states.length()
  }
  n
}

///|
/// Build the complete, self-contained HTML5 page.

///|
pub fn render_page(
  d : Diagram,
  mermaid_js : String,
  title : String,
  raw_source : String,
) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
  )
  sb.write_string(
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
  )
  sb.write_string("<title>")
  sb.write_string(title)
  sb.write_string("</title>\n<style>\n")
  sb.write_string(PAGE_CSS)
  sb.write_string("\n</style>\n</head>\n<body>\n")
  sb.write_string("<header>\n<h1>")
  sb.write_string(meta_of(d, "target"))
  sb.write_string("<span class=\"badge\">Mermaid &rarr; HTML5</span></h1>\n")
  sb.write_string("<div class=\"sub\">version ")
  sb.write_string(meta_of(d, "version"))
  sb.write_string(" &middot; moonbit ")
  sb.write_string(meta_of(d, "moonbit"))
  sb.write_string(" &middot; scanned ")
  sb.write_string(meta_of(d, "scanned_at"))
  sb.write_string(
    "</div>\n<div class=\"stats\" id=\"stats\"></div>\n</header>\n",
  )
  sb.write_string("<main>\n<aside>\n")
  sb.write_string("<div class=\"card\"><h3>Find a file</h3>\n")
  sb.write_string(
    "<input type=\"search\" id=\"fsearch\" placeholder=\"filter by path or name\" autocomplete=\"off\"></div>\n",
  )
  sb.write_string("<div id=\"filelist\"></div>\n")
  sb.write_string("<div class=\"card\"><h3>Notices</h3>\n")
  sb.write_string(
    "<input type=\"search\" id=\"nsearch\" placeholder=\"filter notices\" autocomplete=\"off\">\n",
  )
  sb.write_string(
    "<div id=\"noticelist\" style=\"max-height:26vh;overflow:auto;margin-top:8px\"></div></div>\n",
  )
  sb.write_string("<div class=\"card\" id=\"metacard\"></div>\n</aside>\n")
  sb.write_string("<section class=\"section\">\n")
  sb.write_string("<div class=\"tabbar\">\n")
  sb.write_string(
    "<button id=\"tab-overview\" class=\"on\">Overview</button>\n",
  )
  sb.write_string("<button id=\"tab-detail\">File detail</button>\n")
  sb.write_string("<button id=\"tab-source\">Source</button>\n")
  sb.write_string("<span class=\"spacer\"></span>\n<div class=\"toolbar\">\n")
  sb.write_string(
    "<button id=\"zoom-out\" title=\"Zoom out\">&minus;</button>\n",
  )
  sb.write_string("<button id=\"zoom-in\" title=\"Zoom in\">+</button>\n")
  sb.write_string(
    "<button id=\"zoom-fit\" title=\"Fit to screen\">Fit</button>\n",
  )
  sb.write_string("<button id=\"zoom-1\" title=\"Actual size\">1:1</button>\n")
  sb.write_string(
    "<button id=\"toggle-text\" title=\"Show or hide diagram text\">Text</button>\n",
  )
  sb.write_string(
    "<button id=\"toggle-panel\" title=\"Show or hide the findings panel\">Notes</button>\n",
  )
  sb.write_string("</div>\n</div>\n")
  sb.write_string("<div class=\"viewport\" id=\"viewport\"></div>\n")
  sb.write_string(
    "<textarea id=\"srctext\" spellcheck=\"false\" style=\"display:none\"></textarea>\n",
  )
  sb.write_string("<div class=\"panel\" id=\"noticepanel\"></div>\n")
  sb.write_string("<div class=\"status\" id=\"status\"></div>\n")
  sb.write_string("<div class=\"readout\" id=\"readout\">100%</div>\n")
  sb.write_string(
    "<div class=\"hint\">drag to pan &middot; wheel to zoom</div>\n",
  )
  sb.write_string("</section>\n</main>\n")
  sb.write_string("<script type=\"application/json\" id=\"meta\">")
  sb.write_string(meta_json(d))
  sb.write_string("</script>\n")
  sb.write_string("<script type=\"application/json\" id=\"counts\">")
  sb.write_string(counts_json(d))
  sb.write_string("</script>\n")
  sb.write_string("<script type=\"application/json\" id=\"files\">")
  sb.write_string(files_json(d))
  sb.write_string("</script>\n")
  sb.write_string("<script type=\"application/json\" id=\"overview-src\">\"")
  sb.write_string(json_escape(overview_source(d)))
  sb.write_string("\"</script>\n")
  sb.write_string("<script type=\"application/json\" id=\"raw-src\">\"")
  sb.write_string(json_escape(raw_source))
  sb.write_string("\"</script>\n")
  if !mermaid_js.is_empty() {
    sb.write_string("<script>")
    // a literal </script> inside the runtime would end the element early
    sb.write_string(mermaid_js.replace_all(old="</script", new="<\\/script"))
    sb.write_string("</script>\n")
    sb.write_string("<script>\n")
    sb.write_string(CLIENT_JS)
    sb.write_string("</script>\n")
  }
  sb.write_string("</body>\n</html>\n")
  sb.to_string()
}
