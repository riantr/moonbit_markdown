///|
/// The link reference definitions of a document.
///
/// A definition is written
///
///     [label]: destination "title"
///
/// and the label may then be used as `[text][label]`, or - when the text is
/// the label itself - as `[label]`. The first definition of a label wins,
/// and a label that is never defined stays literal text.

///|
type Refs = Array[(String, String, String)]

///|
/// The label as it is looked up: case folded, with the whitespace collapsed
/// to single spaces. `[Foo Bar]` and `[foo   bar]` are the same label.
///
fn normalize_label(s : String) -> String {
  let cs = chars(s.to_lower())
  let sb = StringBuilder()
  let mut started = false
  let mut space = false
  for c in cs {
    if is_space(c) {
      if started {
        space = true
      }
      continue
    }
    if space {
      sb.write_char(' ')
      space = false
    }
    sb.write_char(c)
    started = true
  }
  sb.to_string()
}

///|
/// The definition of `label`, or None.
///
fn lookup_ref(refs : Refs, label : String) -> (String, String)? {
  let key = normalize_label(label)
  if key.is_empty() {
    return None
  }
  for r in refs {
    if r.0 == key {
      return Some((r.1, r.2))
    }
  }
  None
}

///|
/// Remember a definition, unless the label is already known: the first
/// definition of a label wins.
///
fn add_ref(refs : Refs, label : String, dest : String, title : String) -> Unit {
  let key = normalize_label(label)
  if key.is_empty() {
    return
  }
  for r in refs {
    if r.0 == key {
      return
    }
  }
  refs.push((key, dest, title))
}

///|
/// Pull the link reference definitions out of `lines`.
///
/// A definition may stand on its own, or at the head of a paragraph. The
/// lines it occupies are taken out of the text; what is left is parsed as
/// blocks.
///
/// A definition inside a code block is not a definition, and a definition
/// that follows the text of a paragraph is part of that paragraph: a
/// paragraph is never interrupted by one.
///
fn extract_refs(lines : Array[String]) -> (Refs, Array[String]) {
  let refs : Refs = []
  let rest : Array[String] = []
  let mut i = 0
  // whether the previous line was the text of a paragraph
  let mut paragraph = false
  while i < lines.length() {
    let line = lines[i]
    if is_blank(line) {
      paragraph = false
      rest.push(line)
      i += 1
      continue
    }
    // a code block holds no definitions
    match code_block_end(lines, i) {
      Some(next) => {
        let mut j = i
        while j < next {
          rest.push(lines[j])
          j += 1
        }
        paragraph = false
        i = next
        continue
      }
      None => ()
    }
    if !paragraph && may_start_definition(line) {
      match parse_ref_definition(lines, i) {
        Some((label, dest, title, next)) => {
          add_ref(refs, label, dest, title)
          // the containers the definition stood in stay, without their
          // content
          let mut j = i
          while j < next {
            let (markers, _content) = split_quote_marker(lines[j])
            if !markers.is_empty() {
              rest.push(markers)
            }
            j += 1
          }
          paragraph = false
          i = next
          continue
        }
        None => ()
      }
    }
    rest.push(line)
    paragraph = !starts_block(line)
    i += 1
  }
  (refs, rest)
}

///|
/// Could the line start a link reference definition?
///
/// Only a line that opens with a bracket may, so the check is cheap enough
/// to run on every line of a document.
///
fn may_start_definition(s : String) -> Bool {
  let (_markers, content) = split_quote_marker(s)
  let cs = chars(content)
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' && i < 3 {
    i += 1
  }
  i < cs.length() && cs[i] == '['
}

///|
/// The block quote markers in front of the line, and the rest of it.
///
/// A definition inside a block quote counts for the whole document, so the
/// markers have to be looked through.
///
fn split_quote_marker(s : String) -> (String, String) {
  let cs = chars(s)
  let mut cut = 0
  let mut again = true
  while again {
    again = false
    let mut j = cut
    while j < cs.length() && cs[j] == ' ' && j - cut < 3 {
      j += 1
    }
    if j < cs.length() && cs[j] == '>' {
      j += 1
      if j < cs.length() && cs[j] == ' ' {
        j += 1
      }
      cut = j
      again = true
    }
  }
  (text(cs, 0, cut), text(cs, cut, cs.length()))
}

///|
/// The text of the lines from `i` on, without the block quote markers, and
/// without the blank line that ends a definition.
///
fn def_text(lines : Array[String], i : Int32) -> String {
  let sb = StringBuilder()
  let mut j = i
  while j < lines.length() {
    let (_markers, content) = split_quote_marker(lines[j])
    if j > i && is_blank(content) {
      // a definition may not hold a blank line
      break
    }
    sb.write_string(content)
    sb.write_string("\n")
    j += 1
  }
  sb.to_string()
}

///|
/// Parse a link reference definition at `lines[i]`, if there is one.
/// Returns (label, destination, title, the index after the definition).
///
/// The definition may span several lines: the label, the destination and the
/// title may each be broken off onto the next line, and the title may even
/// hold several lines. Nothing may follow the definition but spaces.
///
fn parse_ref_definition(
  lines : Array[String],
  i : Int32,
) -> (String, String, String, Int32)? {
  let text = def_text(lines, i)
  let cs = chars(text)
  // up to three spaces of indentation
  let mut a = 0
  while a < cs.length() && cs[a] == ' ' && a < 3 {
    a += 1
  }
  if a >= cs.length() || cs[a] != '[' {
    return None
  }
  // the label: up to the closing bracket, with the escapes resolved
  let mut j = a + 1
  let label = StringBuilder()
  while j < cs.length() {
    let c = cs[j]
    if c == ']' {
      break
    }
    if c == '[' {
      // a label may not hold a bracket
      return None
    }
    if c == '\\' && j + 1 < cs.length() && is_punct(cs[j + 1]) {
      label.write_char(cs[j + 1])
      j += 2
      continue
    }
    if c == '\n' {
      // the label may be broken over lines, but the whitespace of the line
      // ending counts as one space
      label.write_char(' ')
      j += 1
      continue
    }
    label.write_char(c)
    j += 1
  }
  if j >= cs.length() || cs[j] != ']' {
    return None
  }
  let label_text = label.to_string()
  if normalize_label(label_text).is_empty() {
    return None
  }
  // the colon
  let mut k = j + 1
  if k >= cs.length() || cs[k] != ':' {
    return None
  }
  k += 1
  // the destination, with the whitespace in front of it
  k = skip_def_space(cs, k)
  let (dest, after) = match scan_destination(cs, k) {
    Some(x) => x
    None => return None
  }
  // the optional title, which has to be separated from the destination by
  // whitespace
  let mut title = ""
  let mut end = after
  let mut p = after
  while p < cs.length() && (cs[p] == ' ' || cs[p] == '\t') {
    p += 1
  }
  let mut newline = false
  if p < cs.length() && cs[p] == '\n' {
    newline = true
    p += 1
    while p < cs.length() && (cs[p] == ' ' || cs[p] == '\t') {
      p += 1
    }
  }
  if p > after && p < cs.length() && (cs[p] == '"' || cs[p] == '\'' || cs[p] == '(') {
    match scan_ref_title(cs, p) {
      Some((t, after_title)) => {
        // nothing may follow the title but spaces
        let mut q = after_title
        while q < cs.length() && (cs[q] == ' ' || cs[q] == '\t') {
          q += 1
        }
        if q >= cs.length() || cs[q] == '\n' {
          title = t
          end = after_title
        } else if !newline {
          // the title stands on the same line as the destination and
          // something follows it: this is not a definition
          return None
        }
        // else the title stands on a later line and something follows it, so
        // the definition ends at the destination
      }
      None => ()
    }
  }
  // and nothing may follow the definition but spaces
  let mut q = end
  while q < cs.length() && (cs[q] == ' ' || cs[q] == '\t') {
    q += 1
  }
  if q < cs.length() && cs[q] != '\n' {
    return None
  }
  Some((label_text, dest, title, i + line_count(cs, end)))
}

///|
/// Skip the whitespace that may sit between the parts of a definition.
///
/// At most one line ending may be skipped.
///
fn skip_def_space(cs : Chars, k : Int32) -> Int32 {
  let mut j = k
  let mut newline = false
  while j < cs.length() {
    let c = cs[j]
    if c == ' ' || c == '\t' {
      j += 1
      continue
    }
    if c == '\n' {
      if newline {
        break
      }
      newline = true
      j += 1
      continue
    }
    break
  }
  j
}

///|
/// Read the title of a definition at `k`: text between `"`, `'` or `(` and
/// its closing mark. The title may hold line endings.
///
fn scan_ref_title(cs : Chars, k : Int32) -> (String, Int32)? {
  if k >= cs.length() {
    return None
  }
  let open = cs[k]
  let close = if open == '(' { ')' } else { open }
  if open != '"' && open != '\'' && open != '(' {
    return None
  }
  let mut j = k + 1
  let sb = StringBuilder()
  while j < cs.length() {
    let c = cs[j]
    if c == close {
      return Some((sb.to_string(), j + 1))
    }
    if c == '\\' && j + 1 < cs.length() && is_punct(cs[j + 1]) {
      sb.write_char(cs[j + 1])
      j += 2
      continue
    }
    sb.write_char(c)
    j += 1
  }
  None
}

///|
/// The number of lines the text holds, up to `end`.
///
fn line_count(cs : Chars, end : Int32) -> Int32 {
  let mut n = 1
  let mut i = 0
  while i < end && i < cs.length() {
    if cs[i] == '\n' {
      n += 1
    }
    i += 1
  }
  n
}

///|
/// The index after the code block that starts at `lines[i]`, or None when the
/// line does not start one.
///
/// A fenced code block runs to its closing fence, an indented code block to
/// the last line that is indented by four columns.
///
fn code_block_end(lines : Array[String], i : Int32) -> Int32? {
  let line = lines[i]
  if is_shallow(line) {
    match fence_of(line) {
      Some((_, fence_ch, fence_n, _fence_indent)) => {
        let mut j = i + 1
        while j < lines.length() {
          if is_closing_fence(lines[j], fence_ch, fence_n) {
            return Some(j + 1)
          }
          j += 1
        }
        return Some(lines.length())
      }
      None => ()
    }
  }
  if indent_of(line) >= 4 {
    let mut j = i
    let mut last = i
    while j < lines.length() {
      if is_blank(lines[j]) {
        j += 1
        continue
      }
      if indent_of(lines[j]) < 4 {
        break
      }
      last = j
      j += 1
    }
    return Some(last + 1)
  }
  None
}

///|
/// Does the line start a block? A line that starts a block ends the
/// paragraph before it, so a definition may follow it.
///
fn starts_block(line : String) -> Bool {
  if heading_level(line) > 0 {
    return true
  }
  if indent_of(line) < 4 && is_thematic_break(line) {
    return true
  }
  if fence_of(line) is Some(_) {
    return true
  }
  if trimmed(chars(line)).has_prefix(">") {
    return true
  }
  if list_can_interrupt(line) {
    return true
  }
  match html_block_kind(line) {
    Some(kind) => return html_block_interrupts(kind)
    None => ()
  }
  false
}
