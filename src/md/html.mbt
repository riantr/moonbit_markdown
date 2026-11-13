///|
/// HTML5 rendering of the document model.

///|
/// The output is deliberately plain: semantic elements, no inline styles
/// except table alignment, and a class name on every element that a
/// stylesheet may want to target. A Mermaid block becomes
/// `<div class="mermaid">`, which the client-side renderer picks up - that is
/// the seam between this package's Markdown side and its Mermaid side.
///

///|
/// Escape text for HTML content and attribute values.
///
pub fn escape_html(s : String) -> String {
  let sb = StringBuilder()
  for c in s.iter() {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      '\'' => sb.write_string("&#39;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
pub fn render_inline(items : Array[Inline]) -> String {
  let sb = StringBuilder()
  for it in items {
    match it {
      Text(t) => sb.write_string(escape_html(t))
      Code(t) => {
        sb.write_string("<code>")
        sb.write_string(escape_html(t))
        sb.write_string("</code>")
      }
      Emphasis(cs) => {
        sb.write_string("<em>")
        sb.write_string(render_inline(cs))
        sb.write_string("</em>")
      }
      Strong(cs) => {
        sb.write_string("<strong>")
        sb.write_string(render_inline(cs))
        sb.write_string("</strong>")
      }
      Link(href, title, cs) => {
        sb.write_string("<a href=\"")
        sb.write_string(escape_html(href))
        sb.write_string("\"")
        if !title.is_empty() {
          sb.write_string(" title=\"")
          sb.write_string(escape_html(title))
          sb.write_string("\"")
        }
        sb.write_string(">")
        sb.write_string(render_inline(cs))
        sb.write_string("</a>")
      }
      Image(src, alt) => {
        sb.write_string("<img src=\"")
        sb.write_string(escape_html(src))
        sb.write_string("\" alt=\"")
        sb.write_string(escape_html(alt))
        sb.write_string("\">")
      }
      RawHtml(h) => sb.write_string(h)
      HardBreak => sb.write_string("<br>\n")
      SoftBreak => sb.write_string("\n")
    }
  }
  sb.to_string()
}

///|
fn heading_id(text : String) -> String {
  let sb = StringBuilder()
  for c in text.iter() {
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      sb.write_char(c.to_ascii_lowercase())
    } else if c == '-' || c == '_' {
      sb.write_char(c)
    } else if c == ' ' {
      sb.write_char('-')
    }
  }
  sb.to_string()
}

///|
/// Render a list, honouring task list items.
///
/// The paragraphs of a tight list are written without their wrapper, the
/// ones of a loose list with it.

///|
fn render_list(ordered : Bool, loose : Bool, items : Array[ListItem]) -> String {  let sb = StringBuilder()
  let tag = if ordered { "ol" } else { "ul" }
  sb.write_string("<")
  sb.write_string(tag)
  sb.write_string(">")
  for it in items {
    sb.write_string("<li")
    if it.task == 1 {
      sb.write_string(" class=\"task-list-item\"")
    }
    sb.write_string(">")
    if it.task != 0 {
      let checked = if it.task == 2 { " checked" } else { "" }
      sb.write_string("<input type=\"checkbox\" disabled")
      sb.write_string(checked)
      sb.write_string("> ")
    }
    let body = render_blocks_tight(it.blocks, !loose)
    sb.write_string(body)
    sb.write_string("</li>")
  }
  sb.write_string("</")
  sb.write_string(tag)
  sb.write_string(">")
  sb.to_string()
}

///|
pub fn render_blocks(blocks : Array[Block]) -> String {
  render_blocks_tight(blocks, false)
}

///|
/// Render the blocks, with or without the wrapper of the paragraphs.
///
/// The paragraphs of a tight list item are written without their wrapper,
/// even when the item holds other blocks as well.
///
fn render_blocks_tight(blocks : Array[Block], tight : Bool) -> String {
  let sb = StringBuilder()
  let mut first = true
  for b in blocks {
    if !first && tight {
      // the blocks of a tight item stand one after the other, with a line
      // ending between them
      sb.write_string("\n")
    }
    first = false
    match b {
      Heading(level, cs) => {
        sb.write_string("<h")
        sb.write_string(level.to_string())
        sb.write_string(" id=\"")
        sb.write_string(escape_html(heading_id(plain_text(cs))))
        sb.write_string("\">")
        sb.write_string(render_inline(cs))
        sb.write_string("</h")
        sb.write_string(level.to_string())
        sb.write_string(">")
      }
      Paragraph(cs) => {
        if tight {
          sb.write_string(render_inline(cs))
        } else {
          sb.write_string("<p>")
          sb.write_string(render_inline(cs))
          sb.write_string("</p>\n")
        }
      }
      CodeBlock(info, code) => {
        sb.write_string("<pre><code")
        if !info.is_empty() {
          sb.write_string(" class=\"language-")
          sb.write_string(escape_html(first_word(info)))
          sb.write_string("\"")
        }
        sb.write_string(">")
        sb.write_string(escape_html(code))
        sb.write_string("</code></pre>\n")
      }
      Mermaid(src) => {
        sb.write_string("<div class=\"mermaid\">\n")
        sb.write_string(escape_html(src))
        sb.write_string("</div>\n")
      }
      HtmlBlock(h) => {
        sb.write_string(h)
        sb.write_string("\n")
      }
      Quote(bs) => {
        sb.write_string("<blockquote>\n")
        sb.write_string(render_blocks(bs))
        sb.write_string("</blockquote>\n")
      }
      List(ordered, loose, items) => {
        sb.write_string(render_list(ordered, loose, items))
        sb.write_string("\n")
      }
      Rule => sb.write_string("<hr>\n")
      Table(head, align, rows) => {
        sb.write_string("<table>\n<thead>\n<tr>")
        for i in 0..<head.length() {
          sb.write_string("<th")
          let a = if i < align.length() { align[i] } else { "" }
          if !a.is_empty() {
            sb.write_string(" style=\"text-align:")
            sb.write_string(a)
            sb.write_string("\"")
          }
          sb.write_string(">")
          sb.write_string(render_inline(head[i].content))
          sb.write_string("</th>")
        }
        sb.write_string("</tr>\n</thead>\n<tbody>\n")
        for r in rows {
          sb.write_string("<tr>")
          for i in 0..<r.cells.length() {
            sb.write_string("<td")
            let a = if i < align.length() { align[i] } else { "" }
            if !a.is_empty() {
              sb.write_string(" style=\"text-align:")
              sb.write_string(a)
              sb.write_string("\"")
            }
            sb.write_string(">")
            sb.write_string(render_inline(r.cells[i].content))
            sb.write_string("</td>")
          }
          sb.write_string("</tr>\n")
        }
        sb.write_string("</tbody>\n</table>\n")
      }
    }
  }
  sb.to_string()
}

///|
/// Render a Markdown document to an HTML5 fragment.

///|
pub fn render(src : String) -> String {
  render_blocks(parse_document(src))
}

///|
/// A heading entry, used to build a table of contents.

///|
pub struct TocEntry {
  level : Int32
  id : String
  text : String
}

///|
/// Collect the headings of a document, in order.

///|
pub fn collect_toc(blocks : Array[Block]) -> Array[TocEntry] {
  let out : Array[TocEntry] = []
  collect_toc_into(blocks, out)
  out
}

///|
fn collect_toc_into(blocks : Array[Block], out : Array[TocEntry]) -> Unit {
  for b in blocks {
    match b {
      Heading(level, cs) =>
        out.push({
          level,
          id: heading_id(plain_text(cs)),
          text: plain_text(cs),
        })
      Quote(inner) => collect_toc_into(inner, out)
      List(_, _, items) =>
        for it in items {
          collect_toc_into(it.blocks, out)
        }
      _ => ()
    }
  }
}

///|
/// Does this document hold a diagram?
///
/// The mermaid runtime is 2.6 MB, so it is only inlined when the document
/// actually holds a diagram; a document without one stays a few kilobytes.
/// The question is asked of the parsed document rather than of the rendered
/// HTML, so that a document which merely mentions the markup is not mistaken
/// for one that draws a diagram.

///|
pub fn needs_runtime(blocks : Array[Block]) -> Bool {
  for b in blocks {
    match b {
      Mermaid(_) => return true
      Quote(inner) => {
        if needs_runtime(inner) {
          return true
        }
      }
      List(_, _, items) => {
        for it in items {
          if needs_runtime(it.blocks) {
            return true
          }
        }
      }
      _ => ()
    }
  }
  false
}

///|
/// The stylesheet that puts each diagram on a page of its own.
///
/// A diagram that is wider than the page cannot be printed at a readable size
/// without either shrinking it past legibility or letting the browser break it
/// across two sheets. This mode gives the drawing a page to itself and scales
/// it down until it fits, so one diagram is always exactly one page.
///
/// Only the print media block is affected: on screen the page keeps reading as
/// a document, and the PDF gets the figure pages because that is the medium the
/// rule was written for.
///
pub const FIGURE_CSS : String = "@media print{main.figures-one-page .mermaid{break-before:page;break-after:page;page-break-before:always;page-break-after:always;height:265mm;display:flex;align-items:center;justify-content:center;margin:0;overflow:hidden}main.figures-one-page .mermaid svg{max-width:100%!important;max-height:265mm!important;width:auto!important;height:auto!important}}"

///|
/// The default stylesheet, used by `render_page`.

///|
pub const DEFAULT_CSS : String = "@page{size:A4 portrait;margin:12mm}html{box-sizing:border-box}*{box-sizing:inherit}body{margin:0;background:#fff;color:#1c1c1c;font:16px/1.65 -apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif}main{max-width:52em;margin:0 auto;padding:48px 24px 96px}h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.6em 0 .6em}h1{font-size:2em}h2{font-size:1.5em}h3{font-size:1.2em}p{margin:0 0 1em}a{color:#0b5cad}code{background:#f4f4f6;border-radius:4px;padding:.15em .35em;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.88em}pre{background:#f7f7f9;border:1px solid #e3e3e8;border-radius:8px;padding:14px 16px;overflow:auto}pre code{background:none;padding:0;font-size:.86em}blockquote{margin:1.2em 0;padding:.2em 1em;border-left:4px solid #d8d8e0;color:#555}hr{border:0;border-top:1px solid #e3e3e8;margin:2em 0}table{border-collapse:collapse;width:100%;margin:1.2em 0;font-size:.94em}th,td{border-bottom:1px solid #e3e3e8;padding:6px 10px;text-align:left}th{background:#f7f7f9}ul,ol{padding-left:1.4em}.task-list-item{list-style:none}.mermaid{margin:1.5em 0;text-align:center}.mermaid svg{max-width:100%;height:auto}@media print{body{font-size:11pt}main{max-width:none;padding:0}a{color:inherit;text-decoration:none}pre,blockquote,table{break-inside:avoid}}"

///|
/// Wrap a rendered fragment in a complete, self-contained HTML5 document.

///|
/// `mermaid_js` is inlined verbatim when given; a document without it still
/// renders, but its Mermaid blocks stay as source text.

///|
pub fn render_page(
  title : String,
  body : String,
  mermaid_js : String,
  figures_one_page? : Bool = false,
) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
  )
  sb.write_string(
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
  )
  sb.write_string("<title>")
  sb.write_string(escape_html(title))
  sb.write_string("</title>\n<style>\n")
  sb.write_string(DEFAULT_CSS)
  if figures_one_page {
    sb.write_string("\n")
    sb.write_string(FIGURE_CSS)
  }
  sb.write_string("\n</style>\n</head>\n<body>\n")
  if figures_one_page {
    // the class is what the figure rules hang on: the body is untouched, so
    // the same Markdown renders the same way in both modes
    sb.write_string("<main class=\"figures-one-page\">\n")
  } else {
    sb.write_string("<main>\n")
  }
  sb.write_string(body)
  sb.write_string("</main>\n")
  if !mermaid_js.is_empty() {
    sb.write_string("<script>")
    sb.write_string(mermaid_js)
    sb.write_string("</script>\n")
    sb.write_string("<script>\n")
    sb.write_string(MERMAID_BOOTSTRAP)
    sb.write_string("</script>\n")
  }
  sb.write_string("</body>\n</html>\n")
  sb.to_string()
}

///|
/// The client-side bootstrap that turns `<div class="mermaid">` into SVG.

///|
pub const MERMAID_BOOTSTRAP : String = "(function(){if(!window.mermaid){return}window.mermaid.initialize({startOnLoad:false,maxTextSize:20000000,maxEdges:500000});var nodes=[].slice.call(document.querySelectorAll('div.mermaid'));var seq=0;function renderOne(el){var src=el.textContent;var id='mmd_'+(++seq);return window.mermaid.render(id,src).then(function(r){var holder=document.createElement('div');holder.innerHTML=r.svg;var svg=holder.querySelector('svg');el.innerHTML='';el.appendChild(svg)}).catch(function(e){el.textContent='diagram failed to render: '+e})}nodes.reduce(function(p,el){return p.then(function(){return renderOne(el)})},Promise.resolve())})();"
