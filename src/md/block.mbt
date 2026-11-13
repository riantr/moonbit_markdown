///|
/// Block level parsing: headings, paragraphs, fenced and indented code,
/// block quotes, lists, tables, thematic breaks, raw HTML blocks.

///|
/// The parser works on an array of lines and recurses on the *content* of a
/// container: a block quote's lines are stripped of their `>` markers and
/// re-parsed, a list item's lines are stripped of their indentation and
/// re-parsed. There is exactly one block parser, applied to successively
/// simpler line sets.
///
fn is_blank(s : String) -> Bool {
  trimmed(chars(s)).is_empty()
}

///|
/// The number of columns a line is indented by.
///
/// A tab is not one character but a jump to the next multiple of four
/// columns, which is what "four spaces of indentation" means. Counting
/// characters instead would make a tab look like a single column, and an
/// indented code block would come out as a paragraph.

fn indent_of(s : String) -> Int32 {
  let cs = chars(s)
  let mut col = 0
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if c == ' ' {
      col += 1
    } else if c == '\t' {
      col = (col / 4 + 1) * 4
    } else {
      break
    }
    i += 1
  }
  col
}

///|
/// Is the line indented by at most three columns?
///
/// Every leaf block except an indented code block may be indented by up to
/// three columns. Four columns of indentation make the line a code block
/// instead, which is why `    ***` is code and not a thematic break.

fn is_shallow(s : String) -> Bool {
  indent_of(s) <= 3
}

///|
/// The line with `n` columns of indentation removed.
///
/// A tab that straddles the boundary - the part of it that falls inside the
/// removed indentation and the part that falls outside - becomes spaces: the
/// columns that survive are still there, only widened.

fn strip_indent(s : String, n : Int32) -> String {
  let cs = chars(s)
  let sb = StringBuilder()
  let mut col = 0
  let mut i = 0
  while i < cs.length() && col < n {
    let c = cs[i]
    if c == ' ' {
      col += 1
      i += 1
      continue
    }
    if c == '\t' {
      let end = (col / 4 + 1) * 4
      if end <= n {
        col = end
        i += 1
        continue
      }
      let mut k = col
      while k < n {
        sb.write_char(' ')
        k += 1
      }
      col = n
      i += 1
      continue
    }
    break
  }
  while i < cs.length() {
    sb.write_char(cs[i])
    i += 1
  }
  sb.to_string()
}

///|
/// The ATX heading level of a line, or 0 when the line is not a heading.
///
fn heading_level(s : String) -> Int32 {
  let cs = chars(s)
  // a heading may be indented by up to three columns
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' && i < 3 {
    i += 1
  }
  if i > 3 || i >= cs.length() {
    return 0
  }
  let mut n = 0
  while i + n < cs.length() && cs[i + n] == '#' {
    n += 1
  }
  if n == 0 || n > 6 {
    return 0
  }
  if i + n < cs.length() && cs[i + n] != ' ' && cs[i + n] != '\t' {
    return 0
  }
  n
}

///|
/// The fence info of a code fence line, or None.
/// Returns (info string, fence character, fence length, indentation).
///
/// The info string of a fence of backticks may not hold a backtick, so that
/// a line of inline code is not mistaken for a fence.
///
fn fence_of(s : String) -> (String, Char, Int32, Int32)? {
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' {
    i += 1
  }
  if i > 3 {
    return None
  }
  let c = if i < cs.length() && cs[i] == '`' {
    '`'
  } else if i < cs.length() && cs[i] == '~' {
    '~'
  } else {
    return None
  }
  let mut n = 0
  while i + n < cs.length() && cs[i + n] == c {
    n += 1
  }
  // a fence needs at least three characters, so that an inline code span
  // like `x` is not mistaken for a code block
  if n < 3 {
    return None
  }
  let info = trimmed(chars(text(cs, i + n, cs.length())))
  if c == '`' && info.contains("`") {
    return None
  }
  Some((info, c, n, i))
}

///|
/// Is the line the closing fence of a code block?
///
/// The fence may be indented by up to three spaces. Nothing but spaces and
/// tabs may follow it, so that a line of code that starts with a fence stays
/// code.
///
fn is_closing_fence(
  s : String,
  fence_ch : Char,
  fence_n : Int32,
) -> Bool {
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' {
    i += 1
  }
  if i > 3 {
    return false
  }
  let mut n = 0
  while i + n < cs.length() && cs[i + n] == fence_ch {
    n += 1
  }
  if n < fence_n {
    return false
  }
  let mut k = i + n
  while k < cs.length() {
    let c = cs[k]
    if c != ' ' && c != '\t' {
      return false
    }
    k += 1
  }
  true
}

///|
/// Is the line a thematic break (`---`, `***`, `___`)?
///
fn is_thematic_break(s : String) -> Bool {
  let cs = chars(s)
  let mut a = 0
  let mut b = cs.length()
  while a < b && is_space(cs[a]) {
    a += 1
  }
  while b > a && is_space(cs[b - 1]) {
    b -= 1
  }
  if b - a < 3 {
    return false
  }
  let c = cs[a]
  if c != '-' && c != '*' && c != '_' {
    return false
  }
  let mut n = 0
  let mut i = a
  while i < b {
    if cs[i] == c {
      n += 1
    } else if cs[i] != ' ' && cs[i] != '\t' {
      return false
    }
    i += 1
  }
  n >= 3
}

///|
/// The list marker of a line, or None.
/// Returns (ordered?, marker character, number, marker width, content offset).
///
/// The marker character matters: a bullet list changes character starts a
/// new list, and so does an ordered list changing from `.` to `)`. The
/// number does not: `1.` and `2.` belong to the same list.
///
fn list_marker(s : String) -> (Bool, Char, Int32, Int32, Int32)? {
  let cs = chars(s)
  let mut a = 0
  while a < cs.length() && cs[a] == ' ' {
    a += 1
  }
  // a list marker may be indented by up to three columns; a deeper one
  // makes the line a code block
  if a > 3 || a >= cs.length() {
    return None
  }
  let c = cs[a]
  if c == '-' || c == '*' || c == '+' {
    // a thematic break is not a list item
    if is_thematic_break(s) {
      return None
    }
    if a + 1 >= cs.length() {
      // the marker stands alone: the content starts one column after it
      return Some((false, c, 0, 1, 2))
    }
    if cs[a + 1] != ' ' && cs[a + 1] != '\t' {
      return None
    }
    return Some((false, c, 0, 1, content_offset(cs, a + 1, 1)))
  }
  // ordered: 1. or 1)
  let mut n = 0
  while a + n < cs.length() && cs[a + n].is_ascii_digit() {
    n += 1
  }
  if n == 0 || n > 9 || a + n >= cs.length() {
    return None
  }
  let d = cs[a + n]
  if d != '.' && d != ')' {
    return None
  }
  // the number of the marker, as far as it fits in an Int32
  let mut number = 0
  for i in 0..<n {
    number = number * 10 + (cs[a + i].to_int() - 48)
  }
  if a + n + 1 >= cs.length() {
    // the marker stands alone: the content starts one column after it
    return Some((true, d, number, n + 1, n + 2))
  }
  if cs[a + n + 1] != ' ' && cs[a + n + 1] != '\t' {
    return None
  }
  Some((true, d, number, n + 1, content_offset(cs, a + n + 1, n + 1)))
}

///|
/// The offset of the content of a list item, counted from the marker.
///
/// The content starts after the marker and the spaces that follow it. Up to
/// four spaces count, so that the blocks that follow the item have to be
/// indented by that many columns. A wider gap leaves the content one column
/// after the marker, and the rest of the gap belongs to the text.
///
fn content_offset(cs : Chars, at : Int32, width : Int32) -> Int32 {
  let mut n = 0
  let mut p = at
  while p < cs.length() && (cs[p] == ' ' || cs[p] == '\t') && n < 5 {
    n += 1
    p += 1
  }
  if n == 0 {
    // the marker stands alone: the item has no content of its own, and its
    // content starts one column after the marker
    return width + 1
  }
  if n > 4 {
    return width + 1
  }
  width + n
}

///|
/// Can this line start a list that interrupts a paragraph?
///
/// An ordered list may only interrupt a paragraph when it starts with 1, and
/// a list item may only interrupt a paragraph when it is not empty. Both
/// rules are what keeps
///
///     The number of windows in my house is
///     14.  The number of doors is 6.
///
/// from becoming a paragraph followed by a list.
///
fn list_can_interrupt(s : String) -> Bool {
  match list_marker(s) {
    Some((ordered, _ch, number, _w, off)) => {
      if ordered && number != 1 {
        return false
      }
      let cs = chars(s)
      let mut a = 0
      while a < cs.length() && cs[a] == ' ' {
        a += 1
      }
      !trimmed(chars(text(cs, a + off, cs.length()))).is_empty()
    }
    None => false
  }
}

///|
/// Is the line a table delimiter row (`| --- | :-: |`)?
/// Returns the alignment of each column.
///
fn table_alignments(s : String) -> Array[String]? {
  let t = trimmed(chars(s))
  if !t.contains("-") || !t.contains("|") {
    return None
  }
  let cells = split_table_row(t)
  if cells.is_empty() {
    return None
  }
  let out : Array[String] = []
  for c in cells {
    let v = trimmed(chars(c))
    if v.is_empty() {
      return None
    }
    let left = v.has_prefix(":")
    let right = v.has_suffix(":")
    let core0 = if left { v[1:v.length()] } else { v }
    let core = if right && core0.length() > 0 {
      core0[0:core0.length() - 1]
    } else {
      core0
    }
    if core.is_empty() || !core.all(fn(ch) { ch == '-' }) {
      return None
    }
    if left && right {
      out.push("center")
    } else if right {
      out.push("right")
    } else if left {
      out.push("left")
    } else {
      out.push("")
    }
  }
  Some(out)
}

///|
/// Split a table row on unescaped pipes, dropping the outer ones.
///
fn split_table_row(s : String) -> Array[String] {
  let out : Array[String] = []
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && is_space(cs[i]) {
    i += 1
  }
  let cur = StringBuilder()
  if i < cs.length() && cs[i] == '|' {
    i += 1
  }
  while i < cs.length() {
    let c = cs[i]
    if c == '\\' && i + 1 < cs.length() && cs[i + 1] == '|' {
      cur.write_char('|')
      i += 2
      continue
    }
    if c == '|' {
      out.push(cur.to_string())
      cur.reset()
      i += 1
      continue
    }
    cur.write_char(c)
    i += 1
  }
  // a row that ends with '|' has no cell after it
  let last = cur.to_string()
  if !last.trim().is_empty() {
    out.push(last)
  }
  out
}

///|
/// The block level HTML tags: a line that opens one of them starts an HTML
/// block, whatever else is on the line.
///
fn block_tags() -> Array[String] {
  [
    "address", "article", "aside", "base", "basefont", "blockquote", "body",
    "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
    "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
    "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header",
    "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem",
    "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search",
    "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead",
    "title", "tr", "track", "ul",
  ]
}

///|
/// Parse a whole document.
///
/// The link reference definitions are pulled out first, because a paragraph
/// may use a label that is defined further down the document.
///
pub fn parse_document(src : String) -> Array[Block] {
  let (refs, rest) = extract_refs(split_lines(src))
  parse_blocks(rest, refs)
}

///|
fn parse_blocks(lines : Array[String], refs : Refs) -> Array[Block] {
  let out : Array[Block] = []
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if is_blank(line) {
      i += 1
      continue
    }
    // ---- fenced code / mermaid
    if is_shallow(line) {
      match fence_of(line) {
        Some((info, fence_ch, fence_n, fence_indent)) => {
          let body = StringBuilder()
          let mut j = i + 1
          while j < lines.length() {
            let l = lines[j]
            if is_closing_fence(l, fence_ch, fence_n) {
              j += 1
              break
            }
            // the indentation of the opening fence is not part of the code
            body.write_string(strip_indent(l, fence_indent))
            body.write_string("\n")
            j += 1
          }
          let content = body.to_string()
          if info.to_lower() == "mermaid" {
            out.push(Mermaid(content))
          } else {
            out.push(CodeBlock(info, content))
          }
          i = j
          continue
        }
        None => ()
      }
    }
    // ---- ATX heading
    let hl = if is_shallow(line) { heading_level(line) } else { 0 }
    if hl > 0 {
      let raw = trimmed(chars(line))
      let rawc = chars(raw)
      let text_after = trimmed(chars(slice(raw, hl, rawc.length())))
      out.push(Heading(hl, parse_inline_refs(strip_closing_hashes(text_after), refs)))
      i += 1
      continue
    }
    // ---- thematic break
    if is_shallow(line) && is_thematic_break(line) {
      out.push(Rule)
      i += 1
      continue
    }
    // ---- block quote
    if is_shallow(line) && trimmed(chars(line)).has_prefix(">") {
      let body : Array[String] = []
      let mut j = i
      while j < lines.length() {
        let l = lines[j]
        let t = trimmed(chars(l))
        if t.has_prefix(">") {
          let tc = chars(t)
          let mut k = 1
          if k < tc.length() && tc[k] == ' ' {
            k += 1
          }
          body.push(text(tc, k, tc.length()))
          j += 1
          continue
        }
        // lazy continuation: a non-blank line continues the quote, but only
        // when the quote ends with a paragraph: a code block inside the quote
        // ends with the quote
        if !is_blank(l) &&
           !is_block_start(l) &&
           setext_level(l) == 0 &&
           ends_with_paragraph(body) {
          body.push(l)
          j += 1
          continue
        }
        break
      }
      out.push(Quote(parse_blocks(body, refs)))
      i = j
      continue
    }
    // ---- list
    if list_marker(line) is Some(_) {
      let (blk, next) = parse_list(lines, i, refs)
      out.push(blk)
      i = next
      continue
    }
    // ---- table
    if line.contains("|") && i + 1 < lines.length() {
      match table_alignments(lines[i + 1]) {
        Some(align) => {
          let head_cells = split_table_row(trimmed(chars(line)))
          let head = head_cells.map(fn(c) {
            TableCell::{ content: parse_inline_refs(trimmed(chars(c)), refs), }
          })
          let rows : Array[TableRow] = []
          let mut j = i + 2
          while j < lines.length() &&
                !is_blank(lines[j]) &&
                lines[j].contains("|") {
            let cells = split_table_row(trimmed(chars(lines[j])))
            rows.push({
              cells: cells.map(fn(c) {
                TableCell::{ content: parse_inline_refs(trimmed(chars(c)), refs), }
              }),
            })
            j += 1
          }
          out.push(Table(head, align, rows))
          i = j
          continue
        }
        None => ()
      }
    }
    // ---- indented code
    if indent_of(line) >= 4 {
      let body = StringBuilder()
      let mut j = i
      let mut last_content = i
      while j < lines.length() {
        let l = lines[j]
        if is_blank(l) {
          body.write_string("\n")
          j += 1
          continue
        }
        if indent_of(l) < 4 {
          break
        }
        body.write_string(strip_indent(l, 4))
        body.write_string("\n")
        last_content = j
        j += 1
      }
      out.push(CodeBlock("", body.to_string()))
      i = last_content + 1
      continue
    }
    // ---- raw HTML block
    match html_block_kind(line) {
      Some(kind) => {
        let body = StringBuilder()
        let mut j = i
        if html_block_ends_at_marker(kind) {
          // the kind ends at its own marker, so the block may hold blank lines
          while j < lines.length() {
            let l = lines[j]
            body.write_string(l)
            body.write_string("\n")
            j += 1
            if html_block_ends(kind, l) {
              break
            }
          }
        } else {
          // the kind ends at the next blank line
          while j < lines.length() && !is_blank(lines[j]) {
            body.write_string(lines[j])
            body.write_string("\n")
            j += 1
          }
        }
        out.push(HtmlBlock(body.to_string()))
        i = j
        continue
      }
      None => ()
    }
    // ---- paragraph
    let para = StringBuilder()
    let mut j = i
    // a setext heading underline turns the paragraph into a heading
    let mut setext = 0
    while j < lines.length() {
      let l = lines[j]
      if is_blank(l) {
        break
      }
      if j > i {
        let sl = setext_level(l)
        if sl > 0 {
          setext = sl
          j += 1
          break
        }
        if is_block_start(l) {
          break
        }
      }
      if j > i {
        para.write_string("\n")
      }
      // only the left side is trimmed: two trailing spaces make a hard break
      para.write_string(ltrim(chars(l)))
      j += 1
    }
    if setext > 0 {
      out.push(Heading(setext, parse_inline_refs(rtrim(para.to_string()), refs)))
    } else {
      out.push(Paragraph(parse_inline_refs(rtrim(para.to_string()), refs)))
    }
    i = j
  }
  out
}

///|
/// Does the block quote end with a paragraph?
///
/// A line that continues the quote without its marker is a lazy
/// continuation, and that may only continue a paragraph. A code block inside
/// the quote ends when the quote ends, and a blank line closes the
/// paragraph, so neither may be continued that way.
///
fn ends_with_paragraph(body : Array[String]) -> Bool {
  if body.length() == 0 {
    return false
  }
  let last = body[body.length() - 1]
  if is_blank(last) {
    return false
  }
  if indent_of(last) >= 4 {
    return false
  }
  if fence_of(last) is Some(_) {
    return false
  }
  true
}

///|
/// The text without the spaces and tabs at its end.
///
/// The spaces at the end of a block are not part of its text: they would
/// make a line break at the end of the block a hard break, and there is no
/// line break at the end of a block.
///
fn rtrim(s : String) -> String {
  let cs = chars(s)
  let mut b = cs.length()
  while b > 0 && (cs[b - 1] == ' ' || cs[b - 1] == '\t') {
    b -= 1
  }
  text(cs, 0, b)
}

///|
/// The level of a setext heading underline, or 0 when the line is not one.
///
/// A setext heading is a paragraph followed by a line of `=` (level 1) or
/// `-` (level 2). The line may be indented by up to three columns.
///
fn setext_level(s : String) -> Int32 {
  let cs = chars(s)
  let mut a = 0
  while a < cs.length() && cs[a] == ' ' {
    a += 1
  }
  if a > 3 || a >= cs.length() {
    return 0
  }
  let c = cs[a]
  if c != '=' && c != '-' {
    return 0
  }
  let mut b = cs.length()
  while b > a && is_space(cs[b - 1]) {
    b -= 1
  }
  let mut i = a
  while i < b {
    if cs[i] != c {
      return 0
    }
    i += 1
  }
  if c == '=' {
    1
  } else {
    2
  }
}

///|
/// Does this line start a new block, i.e. interrupt a paragraph?
///
fn is_block_start(s : String) -> Bool {
  if is_blank(s) {
    return true
  }
  // a line that is indented by four columns or more is an indented code
  // block, and an indented code block cannot interrupt a paragraph
  if indent_of(s) >= 4 {
    return false
  }
  if heading_level(s) > 0 {
    return true
  }
  if is_thematic_break(s) {
    return true
  }
  if fence_of(s) is Some(_) {
    return true
  }
  if trimmed(chars(s)).has_prefix(">") {
    return true
  }
  if list_can_interrupt(s) {
    return true
  }
  // every kind of HTML block but the one that stands alone on its line may
  // interrupt a paragraph
  match html_block_kind(s) {
    Some(kind) => return html_block_interrupts(kind)
    None => ()
  }
  false
}

///|
/// The text of a heading without the closing sequence of hashes.
///
/// The closing sequence has to be separated from the text by a space, so
/// that `# foo#` keeps its hash. A hash that follows a backslash is part of
/// the text as well, because the escape makes it a literal hash.
///
fn strip_closing_hashes(s : String) -> String {
  let cs = chars(s)
  let mut b = cs.length()
  while b > 0 && cs[b - 1] == '#' {
    b -= 1
  }
  if b == cs.length() {
    return s
  }
  if b == 0 {
    return ""
  }
  if cs[b - 1] != ' ' && cs[b - 1] != '\t' {
    return s
  }
  trimmed(chars(text(cs, 0, b)))
}

///|
/// Parse a list starting at `i`. Returns (the list block, the index after it).
///
/// A list goes on over a blank line when the next item is of the same kind,
/// and such a list is loose: the paragraphs of its items are written as
/// paragraphs. A list is loose as well when one of its items holds two
/// blocks with a blank line between them.
///
fn parse_list(lines : Array[String], i : Int32, refs : Refs) -> (Block, Int32) {
  let first = lines[i]
  let (ordered, first_ch, _, _, _) = list_marker(first).unwrap()
  let items : Array[ListItem] = []
  let mut j = i
  let mut loose = false
  while j < lines.length() {
    let l = lines[j]
    let marker = list_marker(l)
    if marker is None {
      // a blank line between two items of the same list does not end the list
      if is_blank(l) {
        let mut k = j
        while k < lines.length() && is_blank(lines[k]) {
          k += 1
        }
        if k < lines.length() {
          match list_marker(lines[k]) {
            Some((is_ord, mch, _, _, _)) => {
              if is_ord == ordered && mch == first_ch {
                loose = true
                j = k
                continue
              }
            }
            None => ()
          }
        }
      }
      break
    }
    let (is_ord, mch, _, _, content_off) = marker.unwrap()
    if is_ord != ordered || mch != first_ch {
      // a different kind of marker starts a different list
      break
    }
    let lc = chars(l)
    let mut a = 0
    while a < lc.length() && lc[a] == ' ' {
      a += 1
    }
    let content_indent = a + content_off
    let mut first_content = if a + content_off <= lc.length() {
      text(lc, a + content_off, lc.length())
    } else {
      ""
    }
    // task list marker
    let mut task = 0
    if first_content == "[ ]" {
      task = 1
      first_content = ""
    } else if first_content == "[x]" || first_content == "[X]" {
      task = 2
      first_content = ""
    } else if first_content.has_prefix("[ ] ") {
      task = 1
      first_content = first_content[4:first_content.length()].to_owned()
    } else if first_content.has_prefix("[x] ") ||
      first_content.has_prefix("[X] ") {
      task = 2
      first_content = first_content[4:first_content.length()].to_owned()
    }
    let body : Array[String] = [first_content]
    // a list item may begin with at most one blank line
    let empty_item = first_content.is_empty()
    j += 1
    while j < lines.length() {
      let n = lines[j]
      if is_blank(n) {
        if empty_item {
          break
        }
        // a blank line ends the item unless the next line continues it
        let mut k = j
        while k < lines.length() && is_blank(lines[k]) {
          k += 1
        }
        if k < lines.length() && indent_of(lines[k]) >= content_indent {
          let mut blanks = k - j
          while blanks > 0 {
            body.push("")
            blanks -= 1
          }
          // the item holds two blocks with a blank line between them, so the
          // list is loose
          loose = true
          j = k
          continue
        }
        break
      }
      if indent_of(n) >= content_indent {
        body.push(strip_indent(n, content_indent))
        j += 1
        continue
      }
      if list_marker(n) is Some(_) || is_block_start(n) {
        break
      }
      // lazy paragraph continuation
      body.push(trimmed(chars(n)))
      j += 1
    }
    items.push({ blocks: parse_blocks(body, refs), task, })
  }
  (List(ordered, loose, items), j)
}
