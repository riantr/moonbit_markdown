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
fn indent_of(s : String) -> Int32 {
  let cs = chars(s)
  let mut n = 0
  while n < cs.length() && cs[n] == ' ' {
    n += 1
  }
  n
}

///|
fn strip_indent(s : String, n : Int32) -> String {
  let cs = chars(s)
  let mut i = 0
  let mut cut = 0
  while i < cs.length() && cut < n && cs[i] == ' ' {
    i += 1
    cut += 1
  }
  text(cs, i, cs.length())
}

///|
/// The ATX heading level of a line, or 0 when the line is not a heading.
///
fn heading_level(s : String) -> Int32 {
  let cs = chars(s)
  let mut n = 0
  while n < cs.length() && cs[n] == '#' {
    n += 1
  }
  if n == 0 || n > 6 {
    return 0
  }
  if n < cs.length() && cs[n] != ' ' && cs[n] != '\t' {
    return 0
  }
  n
}

///|
/// The fence info of a code fence line, or None.
/// Returns (info string, fence character, fence length).
///
fn fence_of(s : String) -> (String, Char, Int32)? {
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' {
    i += 1
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
  Some((info, c, n))
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
/// Returns (ordered?, marker width, content offset).
///
fn list_marker(s : String) -> (Bool, Int32, Int32)? {
  let cs = chars(s)
  let mut a = 0
  while a < cs.length() && cs[a] == ' ' {
    a += 1
  }
  if a >= cs.length() {
    return None
  }
  let c = cs[a]
  if c == '-' || c == '*' || c == '+' {
    // a thematic break is not a list item
    if is_thematic_break(s) {
      return None
    }
    if a + 1 >= cs.length() {
      return Some((false, 1, 1))
    }
    if cs[a + 1] == ' ' || cs[a + 1] == '\t' {
      return Some((false, 1, 2))
    }
    return None
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
  if a + n + 1 >= cs.length() {
    return Some((true, n + 1, n + 1))
  }
  if cs[a + n + 1] == ' ' || cs[a + n + 1] == '\t' {
    return Some((true, n + 1, n + 2))
  }
  None
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
/// Does the line start a raw HTML block?
///
fn is_html_block_start(s : String) -> Bool {
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' {
    i += 1
  }
  if i >= cs.length() || cs[i] != '<' {
    return false
  }
  if cs.length() >= i + 4 &&
    cs[i + 1] == '!' &&
    cs[i + 2] == '-' &&
    cs[i + 3] == '-' {
    return true
  }
  let mut j = i + 1
  if j < cs.length() && cs[j] == '/' {
    j += 1
  }
  let start = j
  while j < cs.length() && cs[j].is_ascii_alphabetic() {
    j += 1
  }
  j > start
}

///|
/// Parse a whole document.
///
pub fn parse_document(src : String) -> Array[Block] {
  parse_blocks(split_lines(src))
}

///|
fn parse_blocks(lines : Array[String]) -> Array[Block] {
  let out : Array[Block] = []
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if is_blank(line) {
      i += 1
      continue
    }
    // ---- fenced code / mermaid
    match fence_of(line) {
      Some((info, fence_ch, fence_n)) => {
        let body = StringBuilder()
        let mut j = i + 1
        while j < lines.length() {
          let l = lines[j]
          let t = trimmed(chars(l))
          let tc = chars(t)
          let mut k = 0
          while k < tc.length() && tc[k] == fence_ch {
            k += 1
          }
          if k >= fence_n && (k == tc.length() || tc[k] == ' ' || tc[k] == '\t') {
            j += 1
            break
          }
          body.write_string(l)
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
    // ---- ATX heading
    let hl = heading_level(line)
    if hl > 0 {
      let raw = trimmed(chars(line))
      let rawc = chars(raw)
      let text_after = trimmed(chars(slice(raw, hl, rawc.length())))
      out.push(Heading(hl, parse_inline(strip_closing_hashes(text_after))))
      i += 1
      continue
    }
    // ---- thematic break
    if is_thematic_break(line) {
      out.push(Rule)
      i += 1
      continue
    }
    // ---- block quote
    if trimmed(chars(line)).has_prefix(">") {
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
        // lazy continuation: a non-blank line continues the quote
        if !is_blank(l) && !is_block_start(l) {
          body.push(l)
          j += 1
          continue
        }
        break
      }
      out.push(Quote(parse_blocks(body)))
      i = j
      continue
    }
    // ---- list
    if list_marker(line) is Some(_) {
      let (blk, next) = parse_list(lines, i)
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
            TableCell::{ content: parse_inline(trimmed(chars(c))), }
          })
          let rows : Array[TableRow] = []
          let mut j = i + 2
          while j < lines.length() &&
                !is_blank(lines[j]) &&
                lines[j].contains("|") {
            let cells = split_table_row(trimmed(chars(lines[j])))
            rows.push({
              cells: cells.map(fn(c) {
                TableCell::{ content: parse_inline(trimmed(chars(c))), }
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
    if is_html_block_start(line) {
      let body = StringBuilder()
      let mut j = i
      while j < lines.length() && !is_blank(lines[j]) {
        body.write_string(lines[j])
        body.write_string("\n")
        j += 1
      }
      out.push(HtmlBlock(body.to_string()))
      i = j
      continue
    }
    // ---- paragraph
    let para = StringBuilder()
    let mut j = i
    while j < lines.length() {
      let l = lines[j]
      if is_blank(l) {
        break
      }
      if j > i && is_block_start(l) {
        break
      }
      if j > i {
        para.write_string("\n")
      }
      // only the left side is trimmed: two trailing spaces make a hard break
      para.write_string(ltrim(chars(l)))
      j += 1
    }
    out.push(Paragraph(parse_inline(para.to_string())))
    i = j
  }
  out
}

///|
/// Does this line start a new block, i.e. interrupt a paragraph?
///
fn is_block_start(s : String) -> Bool {
  if is_blank(s) {
    return true
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
  if list_marker(s) is Some(_) {
    return true
  }
  false
}

///|
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
  if cs[b - 1] == ' ' {
    return trimmed(chars(text(cs, 0, b)))
  }
  text(cs, 0, b)
}

///|
/// Parse a list starting at `i`. Returns (the list block, the index after it).
///
fn parse_list(lines : Array[String], i : Int32) -> (Block, Int32) {
  let first = lines[i]
  let (ordered, _, _) = list_marker(first).unwrap()
  let items : Array[ListItem] = []
  let mut j = i
  while j < lines.length() {
    let l = lines[j]
    let marker = list_marker(l)
    if marker is None {
      break
    }
    let (is_ord, _, content_off) = marker.unwrap()
    if is_ord != ordered {
      break
    }
    let lc = chars(l)
    let mut a = 0
    while a < lc.length() && lc[a] == ' ' {
      a += 1
    }
    let content_indent = a + content_off
    let mut first_content = text(lc, a + content_off, lc.length())
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
    j += 1
    while j < lines.length() {
      let n = lines[j]
      if is_blank(n) {
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
    items.push({ blocks: parse_blocks(body), task, })
  }
  (List(ordered, items), j)
}
