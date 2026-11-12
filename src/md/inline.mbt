///|
/// Inline parsing: emphasis, code spans, links, images, raw HTML, breaks.

///|
/// The scanner walks the text once, over an `Array[Char]` so that indices
/// are character indices (see src/text for why). Code spans, autolinks and
/// raw HTML are recognised before emphasis, because their contents must not
/// be re-parsed (`*` inside a code span is a literal asterisk).

///|
/// Emphasis uses a delimiter run: a run of `*` or `_` opens only if it is
/// followed by non-space and closes only if it is preceded by non-space. The
/// opener and the closer are matched by scanning forward for a run of the
/// same character at least as long as the opener. That is CommonMark's rule
/// simplified to the cases that occur in practice; the deviation is recorded
/// in README.md.
///
/// NOTE: MoonBit has no `if let`; optional values are always matched.
///
priv struct Delim {
  ch : Char
  count : Int32
  can_open : Bool
  can_close : Bool
}

///|
/// Scan a delimiter run at `i`; None when the character is not a delimiter.
///
fn scan_delim(cs : Chars, i : Int32) -> Delim? {
  if i >= cs.length() {
    return None
  }
  let c = cs[i]
  if c != '*' && c != '_' {
    return None
  }
  let mut n = 0
  let mut j = i
  while j < cs.length() && cs[j] == c {
    n += 1
    j += 1
  }
  let before = if i == 0 { ' ' } else { cs[i - 1] }
  let after = if j >= cs.length() { ' ' } else { cs[j] }
  let before_ok = !is_space(before)
  let after_ok = !is_space(after)
  // `_` does not open inside a word: snake_case stays literal.
  let left_flanking = after_ok && (!before_ok || is_punct(before))
  let right_flanking = before_ok && (!after_ok || is_punct(after))
  let can_open = if c == '_' {
    left_flanking && (!right_flanking || is_punct(before))
  } else {
    left_flanking
  }
  let can_close = if c == '_' {
    right_flanking && (!left_flanking || is_punct(after))
  } else {
    right_flanking
  }
  Some({ ch: c, count: n, can_open, can_close, })
}

///|
/// Find the closing run for an opener, starting the search at `from`.
/// Returns (index of the closing run, how many of its characters to use).
///
fn find_closer(cs : Chars, op : Delim, from : Int32) -> (Int32, Int32)? {
  let mut i = from
  while i < cs.length() {
    if cs[i] == '`' {
      // skip over code spans so their asterisks never close an emphasis
      let mut j = i
      while j < cs.length() && cs[j] == '`' {
        j += 1
      }
      let n = j - i
      match find_run(cs, j, '`', n) {
        Some(k) => i = k + n
        None => i = j
      }
      continue
    }
    if cs[i] == '\\' {
      i += 2
      continue
    }
    if cs[i] == op.ch {
      match scan_delim(cs, i) {
        Some(d) => {
          if d.can_close {
            let use_n = if d.count >= op.count { op.count } else { d.count }
            return Some((i, use_n))
          }
          i += d.count
          continue
        }
        None => ()
      }
    }
    i += 1
  }
  None
}

///|
/// Find the next run of `n` copies of `ch` at or after `from`.
///
fn find_run(cs : Chars, from : Int32, ch : Char, n : Int32) -> Int32? {
  let mut i = from
  while i < cs.length() {
    if cs[i] == ch {
      let mut j = i
      while j < cs.length() && cs[j] == ch {
        j += 1
      }
      if j - i == n {
        return Some(i)
      }
      i = j
      continue
    }
    i += 1
  }
  None
}

///|
/// Parse the inline content of `s` into inline nodes.
///
pub fn parse_inline(s : String) -> Array[Inline] {
  parse_inline_chars(chars(s))
}

///|
fn parse_inline_chars(cs : Chars) -> Array[Inline] {
  let out : Array[Inline] = []
  let text_buf = StringBuilder()
  // trailing spaces are held back: two or more of them turn the line break
  // into a hard break, and a single one is dropped before a soft break.
  let mut pending_spaces = 0
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    // ---- a line break ends the line
    if c == '\n' {
      flush_text(out, text_buf)
      if pending_spaces >= 2 {
        out.push(HardBreak)
      } else {
        out.push(SoftBreak)
      }
      pending_spaces = 0
      i += 1
      continue
    }
    // ---- spaces are held back until we know whether they end the line
    if c == ' ' {
      pending_spaces += 1
      i += 1
      continue
    }
    // ---- anything else: the held spaces belong to the text before it
    while pending_spaces > 0 {
      text_buf.write_char(' ')
      pending_spaces -= 1
    }
    // ---- escapes
    if c == '\\' && i + 1 < cs.length() {
      let n = cs[i + 1]
      if is_punct(n) {
        flush_text(out, text_buf)
        text_buf.write_char(n)
        i += 2
        continue
      }
      if n == '\n' {
        flush_text(out, text_buf)
        out.push(HardBreak)
        i += 2
        continue
      }
    }
    // ---- code span
    if c == '`' {
      match scan_code_span(cs, i) {
        Some((code, next)) => {
          flush_text(out, text_buf)
          out.push(Code(code))
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- autolink / raw html
    if c == '<' {
      match scan_autolink(cs, i) {
        Some((link, next)) => {
          flush_text(out, text_buf)
          out.push(Link(link, [Text(link)]))
          i = next
          continue
        }
        None => ()
      }
      match scan_raw_html(cs, i) {
        Some((raw, next)) => {
          flush_text(out, text_buf)
          out.push(RawHtml(raw))
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- image
    if c == '!' && i + 1 < cs.length() && cs[i + 1] == '[' {
      match scan_link(cs, i + 1) {
        Some((label, src, next)) => {
          flush_text(out, text_buf)
          out.push(Image(src, text(cs, label.0, label.1)))
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- link
    if c == '[' {
      match scan_link(cs, i) {
        Some((label, href, next)) => {
          flush_text(out, text_buf)
          out.push(
            Link(href, parse_inline_chars(cs[label.0:label.1].to_owned())),
          )
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- emphasis
    if c == '*' || c == '_' {
      match scan_delim(cs, i) {
        Some(d) =>
          if d.can_open {
            let strong = d.count >= 2
            let opener_len = if strong { 2 } else { 1 }
            let opener = {
              ch: d.ch,
              count: opener_len,
              can_open: d.can_open,
              can_close: d.can_close,
            }
            match find_closer(cs, opener, i + opener_len) {
              Some((close_pos, close_len)) => {
                let inner = parse_inline_chars(
                  cs[i + opener_len:close_pos].to_owned(),
                )
                flush_text(out, text_buf)
                if strong {
                  out.push(Strong(inner))
                } else {
                  out.push(Emphasis(inner))
                }
                i = close_pos + close_len
                continue
              }
              None => ()
            }
          }
        None => ()
      }
    }
    // ---- line break
    if c == '\n' {
      flush_text(out, text_buf)
      if pending_spaces >= 2 {
        out.push(HardBreak)
      } else {
        out.push(SoftBreak)
      }
      pending_spaces = 0
      i += 1
      continue
    }
    text_buf.write_char(c)
    i += 1
  }
  while pending_spaces > 0 {
    text_buf.write_char(' ')
    pending_spaces -= 1
  }
  flush_text(out, text_buf)
  out
}

///|
fn flush_text(out : Array[Inline], sb : StringBuilder) -> Unit {
  let t = sb.to_string()
  if !t.is_empty() {
    out.push(Text(t))
  }
  sb.reset()
}

///|
/// Scan a code span starting at the backtick run at `i`.
/// Returns (content, index after the closing run).
///
fn scan_code_span(cs : Chars, i : Int32) -> (String, Int32)? {
  let mut j = i
  while j < cs.length() && cs[j] == '`' {
    j += 1
  }
  let n = j - i
  match find_run(cs, j, '`', n) {
    Some(k) => {
      let content = text(cs, j, k)
      // strip one leading and trailing space, per CommonMark
      let cc = chars(content)
      let (a, b) = trim_range(cc)
      if b - a >= 2 && cc[a] == ' ' && cc[b - 1] == ' ' {
        Some((text(cc, a + 1, b - 1), k + n))
      } else {
        Some((content, k + n))
      }
    }
    None => None
  }
}

///|
/// Scan an autolink `<scheme:...>` or `<mail@example>`.
///
fn scan_autolink(cs : Chars, i : Int32) -> (String, Int32)? {
  let mut j = i + 1
  while j < cs.length() &&
        cs[j] != '>' &&
        cs[j] != '<' &&
        cs[j] != '\n' &&
        cs[j] != ' ' {
    j += 1
  }
  if j >= cs.length() || cs[j] != '>' {
    return None
  }
  let body = text(cs, i + 1, j)
  if body.is_empty() {
    return None
  }
  let has_scheme = body.contains("://") || body.has_prefix("mailto:")
  let has_mail = body.contains("@") && !body.contains(" ")
  if has_scheme || has_mail {
    Some((body, j + 1))
  } else {
    None
  }
}

///|
/// Scan a raw inline HTML tag at `i`.
///
fn scan_raw_html(cs : Chars, i : Int32) -> (String, Int32)? {
  let mut j = i + 1
  if j < cs.length() && cs[j] == '/' {
    j += 1
  }
  let start = j
  while j < cs.length() && (cs[j].is_ascii_alphabetic() || cs[j] == '-') {
    j += 1
  }
  if j == start {
    return None
  }
  while j < cs.length() && cs[j] != '>' {
    j += 1
  }
  if j >= cs.length() {
    return None
  }
  Some((text(cs, i, j + 1), j + 1))
}

///|
/// Scan a link `[label](target)` starting at the `[`.
/// Returns (label range, target, index after the closing paren).
///
fn scan_link(cs : Chars, i : Int32) -> ((Int32, Int32), String, Int32)? {
  let mut depth = 0
  let mut j = i
  let mut label_end = -1
  while j < cs.length() {
    let c = cs[j]
    if c == '\\' {
      j += 2
      continue
    }
    if c == '[' {
      depth += 1
    } else if c == ']' {
      depth -= 1
      if depth == 0 {
        label_end = j
        break
      }
    }
    j += 1
  }
  if label_end < 0 || label_end + 1 >= cs.length() || cs[label_end + 1] != '(' {
    return None
  }
  let mut k = label_end + 2
  let mut paren = 1
  while k < cs.length() {
    let c = cs[k]
    if c == '\\' {
      k += 2
      continue
    }
    if c == '(' {
      paren += 1
    } else if c == ')' {
      paren -= 1
      if paren == 0 {
        break
      }
    }
    k += 1
  }
  if k >= cs.length() {
    return None
  }
  let raw = chars(text(cs, label_end + 2, k))
  let (a, b) = trim_range(raw)
  let trimmed_target = text(raw, a, b)
  // drop an optional title: href "title"
  let mut target = trimmed_target
  match trimmed_target.find(" \"") {
    Some(q) => target = trimmed_target[0:q].to_owned()
    None => ()
  }
  Some(((i + 1, label_end), target, k + 1))
}

///|
/// Flatten inline nodes to plain text (used for image alt text and headings).
///
pub fn plain_text(items : Array[Inline]) -> String {
  let sb = StringBuilder()
  for it in items {
    match it {
      Text(t) => sb.write_string(t)
      Code(t) => sb.write_string(t)
      Emphasis(cs) => sb.write_string(plain_text(cs))
      Strong(cs) => sb.write_string(plain_text(cs))
      Link(_, cs) => sb.write_string(plain_text(cs))
      Image(_, alt) => sb.write_string(alt)
      RawHtml(_) => ()
      HardBreak => sb.write_string(" ")
      SoftBreak => sb.write_string(" ")
    }
  }
  sb.to_string()
}
