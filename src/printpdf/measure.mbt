///|
/// Measuring a rendered diagram.

///|
/// The browser can lay out a Mermaid diagram, but it cannot tell MoonBit what
/// it laid out: the geometry of 54 nodes in a 16,302 px wide drawing is only
/// known once the drawing exists. So the measurement is a round trip:
///
///   1. MoonBit writes a page that renders the diagram and writes the
///      geometry of every node into a `<pre>` element;
///   2. the browser is asked for its DOM (`--dump-dom`), which arrives as
///      text;
///   3. MoonBit reads the numbers back out of that text and computes the
///      print layout from them.
///
/// The browser measures; it does not decide. Everything that ends up in the
/// document - which page holds what, where the tick marks are, how wide the
/// crop is - is decided here, in MoonBit.

///|
/// The wire format is tab separated text rather than JSON: the numbers come
/// straight out of the browser's geometry, and a tab separated record cannot
/// be broken by an escaping mistake in a nested string.

///|

///|
/// What the browser measured.
///
pub struct Measurement {
  /// the natural size of each measured diagram, in diagram pixels
  dims : Array[(Double, Double)]
  /// the geometry of every node of the first measured diagram
  nodes : Array[NodeBox]
  /// the diagrams that could not be rendered
  errors : Array[String]
}

///|
/// A measurement, built from what the browser reported.
///
pub fn measurement_of(
  dims : Array[(Double, Double)],
  nodes : Array[NodeBox],
) -> Measurement {
  { dims, nodes, errors: [], }
}

///|
/// The size of the first measured diagram, or (0, 0).
///
pub fn full_size(m : Measurement) -> (Double, Double) {
  if m.dims.is_empty() {
    (0.0, 0.0)
  } else {
    m.dims[0]
  }
}

///|
/// The size of the second measured diagram, or (0, 0).
///
pub fn focus_size(m : Measurement) -> (Double, Double) {
  if m.dims.length() < 2 {
    (0.0, 0.0)
  } else {
    m.dims[1]
  }
}

///|
/// The tab separated fields of a line.
///
fn fields(s : String) -> Array[String] {
  let out : Array[String] = []
  for part in s.split("\t") {
    out.push(part.to_owned())
  }
  out
}

///|
/// The text between `<pre id="m">` and the `</pre>` that closes it.
///
fn pre_text(dom : String) -> String {
  let open = "<pre id=\"m\">"
  match dom.find(open) {
    None => ""
    Some(i) => {
      let from = i + open.length()
      let rest = dom[from:dom.length()].to_owned()
      match rest.find("</pre>") {
        None => rest
        Some(j) => rest[0:j].to_owned()
      }
    }
  }
}

///|
/// The measurement back out of the browser's DOM.
///
/// The records are:
///   `D <index> <width> <height>`   the natural size of a diagram
///   `N <index> <id> <x> <y> <w> <h>`  the geometry of one node
///   `E <index> <message>`          a diagram that failed to render
///
/// Only the nodes of the FIRST diagram are kept. Each diagram has its own
/// coordinate space - the focused drawing is 943 px wide and the whole one
/// is 16,302 px - so the geometry of one cannot be read against the other.
///
pub fn parse_measurement(dom : String) -> Measurement {
  let dims : Array[(Double, Double)] = []
  let nodes : Array[NodeBox] = []
  let errors : Array[String] = []
  for line in @text.split_lines(pre_text(dom)) {
    let f = fields(line)
    if f.is_empty() {
      continue
    }
    let tag = f[0]
    if tag == "D" && f.length() >= 4 {
      let index = parse_num(f[1]).to_int()
      while dims.length() <= index {
        dims.push((0.0, 0.0))
      }
      dims[index] = (parse_num(f[2]), parse_num(f[3]))
      continue
    }
    if tag == "N" && f.length() >= 7 {
      if parse_num(f[1]).to_int() != 0 {
        continue
      }
      nodes.push({
        id: f[2],
        x: parse_num(f[3]),
        y: parse_num(f[4]),
        w: parse_num(f[5]),
        h: parse_num(f[6]),
      })
      continue
    }
    if tag == "E" && f.length() >= 3 {
      errors.push(f[2])
    }
  }
  { dims, nodes, errors, }
}

///|
/// The script that renders the diagrams and reports their geometry.
///
fn measure_script() -> String {
  let lines = [
    "(function () {", "  var TAB = String.fromCharCode(9);", "  var NL = String.fromCharCode(10);",
    "  function oneLine(s) {", "    return String(s).split(NL).join(' ').split(TAB).join(' ');",
    "  }", "  window.mermaid.initialize({ startOnLoad: false, maxTextSize: 20000000, maxEdges: 500000, theme: 'default' });",
    "  var SRC = JSON.parse(document.getElementById('srcs').textContent);", "  var out = [];",
    "  var done = 0;", "  function step() {", "    if (done >= SRC.length) {", "      document.getElementById('m').textContent = 'BEGIN' + NL + out.join(NL) + NL + 'END';",
    "      var rt = document.getElementById('rt');", "      if (rt) { rt.remove(); }",
    "      return;", "    }", "    var i = done;", "    done = done + 1;", "    window.mermaid.render('m' + i, SRC[i]).then(function (r) {",
    "      var svg = r.svg;", "      var m = svg.match(/viewBox=\"([^\"]+)\"/);",
    "      if (!m) { out.push('E' + TAB + i + TAB + 'no viewBox'); step(); return; }",
    "      var vb = m[1].split(/[ ,]+/).map(Number);", "      var d = document.createElement('div');",
    "      d.style.cssText = 'position:absolute;left:0;top:0;';", "      d.innerHTML = svg;",
    "      document.body.appendChild(d);", "      var el = d.querySelector('svg');",
    "      el.setAttribute('width', String(vb[2]));", "      el.setAttribute('height', String(vb[3]));",
    "      el.removeAttribute('style');", "      var nodes = [];", "      var list = el.querySelectorAll('g.node');",
    "      for (var k = 0; k < list.length; k++) {", "        var e = list[k];",
    "        var b = null;", "        try { b = e.getBBox(); } catch (err) { continue; }",
    "        if (!b) { continue; }", "        var mtx = e.getCTM();", "        if (!mtx) { continue; }",
    "        var p0 = new DOMPoint(b.x, b.y).matrixTransform(mtx);", "        var p1 = new DOMPoint(b.x + b.width, b.y + b.height).matrixTransform(mtx);",
    "        nodes.push([e.getAttribute('id') || '', p0.x, p0.y, p1.x - p0.x, p1.y - p0.y]);",
    "      }", "      d.remove();", "      out.push('D' + TAB + i + TAB + vb[2] + TAB + vb[3]);",
    "      for (var n = 0; n < nodes.length; n++) {", "        var q = nodes[n];",
    "        out.push('N' + TAB + i + TAB + q[0] + TAB + q[1] + TAB + q[2] + TAB + q[3] + TAB + q[4]);",
    "      }", "      step();", "    }, function (e) {", "      out.push('E' + TAB + i + TAB + oneLine((e && e.message) || String(e)));",
    "      step();", "    });", "  }", "  step();", "})();",
  ]
  lines.join("\n")
}

///|
/// The page that measures the given diagram sources.
///
/// The sources are handed to the page as JSON; the geometry comes back as
/// the text of the `<pre id="m">` element.
///
pub fn measure_page(sources : Array[String], mermaid_js : String) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
  )
  sb.write_string("<title>measure</title>\n</head>\n<body>\n")
  sb.write_string("<pre id=\"m\">PENDING</pre>\n")
  sb.write_string("<script type=\"application/json\" id=\"srcs\">")
  sb.write_string(sources_json(sources))
  sb.write_string("</script>\n")
  sb.write_string("<script id=\"rt\">")
  sb.write_string(mermaid_js.replace_all(old="</script", new="<\\/script"))
  sb.write_string("</script>\n<script>\n")
  sb.write_string(measure_script())
  sb.write_string("\n</script>\n</body>\n</html>\n")
  sb.to_string()
}

///|
/// A list of diagram sources as a JSON array.
///
pub fn sources_json(sources : Array[String]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  for i in 0..<sources.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"")
    sb.write_string(@mermaid.json_escape(sources[i]))
    sb.write_string("\"")
  }
  sb.write_string("]")
  sb.to_string()
}
