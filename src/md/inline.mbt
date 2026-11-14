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
/// opener and the closer are matched by the delimiter stack in emphasis.mbt,
/// which is the rule the specification gives.
///
/// NOTE: MoonBit has no `if let`; optional values are always matched.
///

///|
/// Scan a delimiter run at `i`; None when the character is not a delimiter.
///
/// The run is judged by the flanking rules: it may open when the character
/// after it is not whitespace, and may close when the character before it is
/// not whitespace. An underscore is stricter than a star, because it may
/// only open at the start of a word and only close at the end of one.
///
/// The whitespace and the punctuation are the Unicode ones, not the ASCII
/// ones: the specification counts every character in the `Zs` category as
/// whitespace, and every character in the `P` or `S` categories as
/// punctuation. That is why `*£*bravo.` is not emphasis - `£` is a symbol,
/// and therefore punctuation, so the run cannot close.
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
  let before = if i == 0 { '\n' } else { cs[i - 1] }
  let after = if j >= cs.length() { '\n' } else { cs[j] }
  let before_space = is_unicode_whitespace(before)
  let after_space = is_unicode_whitespace(after)
  let before_punct = is_unicode_punctuation(before)
  let after_punct = is_unicode_punctuation(after)
  // A delimiter run is left-flanking when the character after it is not
  // whitespace, and either that character is not punctuation or the one
  // before the run is whitespace or punctuation. It is right-flanking when
  // the mirror image of that holds.
  //
  // This is what lets `foo*bar*` be emphasis - the `*` sits inside a word,
  // and a star may open there - while `snake_case` stays literal.
  let left_flanking = !after_space &&
    (!after_punct || before_space || before_punct)
  let right_flanking = !before_space &&
    (!before_punct || after_space || after_punct)
  let can_open = if c == '_' {
    left_flanking && (!right_flanking || before_punct)
  } else {
    left_flanking
  }
  let can_close = if c == '_' {
    right_flanking && (!left_flanking || after_punct)
  } else {
    right_flanking
  }
  Some({ ch: c, orig_len: n, can_open, can_close, })
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
  parse_inline_refs(s, [])
}

///|
/// Parse the inline content of `s`, with the document's link reference
/// definitions at hand.
///
fn parse_inline_refs(s : String, refs : Refs) -> Array[Inline] {
  parse_inline_chars(chars(s), refs)
}

///|
fn parse_inline_chars(cs : Chars, refs : Refs) -> Array[Inline] {
  let out : Array[Piece] = []
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
        push_inline(out, HardBreak)
      } else {
        push_inline(out, SoftBreak)
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
        push_inline(out, HardBreak)
        i += 2
        continue
      }
    }
    // ---- a character reference
    if c == '&' {
      match scan_entity(cs, i) {
        Some((value, next)) => {
          flush_text(out, text_buf)
          text_buf.write_string(value)
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- code span
    if c == '`' {
      match scan_code_span(cs, i) {
        Some((code, next)) => {
          flush_text(out, text_buf)
          push_inline(out, Code(code))
          i = next
          continue
        }
        None => {
          // the run of backticks is literal text, and the whole run belongs
          // to it: a shorter run inside it does not open a code span
          flush_text(out, text_buf)
          let mut j = i
          while j < cs.length() && cs[j] == '`' {
            text_buf.write_char('`')
            j += 1
          }
          i = j
          continue
        }
      }
    }
    // ---- autolink / raw html
    if c == '<' {
      match scan_autolink(cs, i) {
        Some((href, label, next)) => {
          flush_text(out, text_buf)
          push_inline(out, Link(href, "", [Text(label)]))
          i = next
          continue
        }
        None => ()
      }
      match scan_raw_html(cs, i) {
        Some((raw, next)) => {
          flush_text(out, text_buf)
          push_inline(out, RawHtml(raw))
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- image
    if c == '!' && i + 1 < cs.length() && cs[i + 1] == '[' {
      // an image may be written like a link: `![alt](src)`, `![alt][label]`
      // or, when the text is the label, `![label]`
      match scan_link(cs, i + 1, true) {
        Some((label, src, _title, next)) => {
          flush_text(out, text_buf)
          push_inline(
            out,
            Image(
              src,
              plain_text(
                parse_inline_chars(cs[label.0:label.1].to_owned(), refs),
              ),
            ),
          )
          i = next
          continue
        }
        None => ()
      }
      match scan_ref_link(cs, i + 1, refs, true) {
        Some((label, src, _title, next)) => {
          flush_text(out, text_buf)
          push_inline(
            out,
            Image(
              src,
              plain_text(
                parse_inline_chars(cs[label.0:label.1].to_owned(), refs),
              ),
            ),
          )
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- link
    if c == '[' {
      match scan_link(cs, i, false) {
        Some((label, href, title, next)) => {
          flush_text(out, text_buf)
          push_inline(
            out,
            Link(
              href,
              title,
              parse_inline_chars(cs[label.0:label.1].to_owned(), refs),
            ),
          )
          i = next
          continue
        }
        None => ()
      }
      match scan_ref_link(cs, i, refs, false) {
        Some((label, href, title, next)) => {
          flush_text(out, text_buf)
          push_inline(
            out,
            Link(
              href,
              title,
              parse_inline_chars(cs[label.0:label.1].to_owned(), refs),
            ),
          )
          i = next
          continue
        }
        None => ()
      }
    }
    // ---- emphasis
    // The delimiter run is only collected here. Which runs pair up, and how
    // many characters of each are used, is decided by the delimiter stack in
    // emphasis.mbt, because the answer depends on the runs that come after
    // this one as well as on the ones before it.
    if c == '*' || c == '_' {
      match scan_delim(cs, i) {
        Some(d) => {
          flush_text(out, text_buf)
          out.push(Run(d))
          i += d.orig_len
          continue
        }
        None => ()
      }
    }
    // ---- line break
    if c == '\n' {
      flush_text(out, text_buf)
      if pending_spaces >= 2 {
        push_inline(out, HardBreak)
      } else {
        push_inline(out, SoftBreak)
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
  resolve_emphasis(out)
}

///|
/// Flush the text collected so far.
///
/// The character references are not decoded here but where they stand, so
/// that an ampersand that follows a backslash escape stays an ampersand.
/// The HTML renderer escapes `&` again on the way out, so a literal `&amp;`
/// survives the round trip.
///
fn flush_text(out : Array[Piece], sb : StringBuilder) -> Unit {
  let t = sb.to_string()
  if !t.is_empty() {
    out.push(Lit(t))
  }
  sb.reset()
}

///|
/// Collect an inline node as a piece.
///
fn push_inline(out : Array[Piece], node : Inline) -> Unit {
  out.push(Node(node))
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
      // the line endings inside a code span become spaces
      let content = content.replace_all(old="\n", new=" ")
      // and a single space is removed from each end, when both ends have one
      // and the content is not all spaces
      let cc = chars(content)
      if cc.length() >= 2 && cc[0] == ' ' && cc[cc.length() - 1] == ' ' {
        let mut all_spaces = true
        for c in cc {
          if c != ' ' {
            all_spaces = false
            break
          }
        }
        if !all_spaces {
          return Some((text(cc, 1, cc.length() - 1), k + n))
        }
      }
      Some((content, k + n))
    }
    None => None
  }
}

///|
/// Is this character one of the characters in `set`?
///
fn char_in(c : Char, set : String) -> Bool {
  let cs = chars(set)
  let mut i = 0
  while i < cs.length() {
    if cs[i] == c {
      return true
    }
    i += 1
  }
  false
}

///|
/// Scan an autolink `<scheme:...>` or `<mail@example>`.
///
/// A URI autolink is a scheme - a letter followed by letters, digits, `+`,
/// `-` and `.` - a colon, and then anything without a space or an angle
/// bracket. An email autolink is a local part, an `@` and a domain.
///
/// The destination of an email autolink is written with a `mailto:` in
/// front, and both destinations are percent-encoded, so that the link can be
/// read back. The text of the link is the address as it was written.
///
fn scan_autolink(cs : Chars, i : Int32) -> (String, String, Int32)? {
  let mut j = i + 1
  while j < cs.length() && cs[j] != '>' && cs[j] != '<' && !is_uri_space(cs[j]) {
    j += 1
  }
  if j >= cs.length() || cs[j] != '>' {
    return None
  }
  let body = text(cs, i + 1, j)
  if body.is_empty() {
    return None
  }
  if is_uri_autolink(body) {
    return Some((encode_uri(body), body, j + 1))
  }
  if is_email_autolink(body) {
    return Some((encode_uri("mailto:" + body), body, j + 1))
  }
  None
}

///|
/// Is this character one that may not appear in a URI? The spaces and the
/// control characters are the ones a URI may not hold.
///
fn is_uri_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c.to_int() < 0x20
}

///|
/// Is this character a letter or a digit?
///
fn is_alphanumeric(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit()
}

///|
/// Is this the body of a URI autolink?
///
/// The scheme is two to thirty-two characters: a letter, then letters,
/// digits, `+`, `-` or `.`. What follows the colon may be anything without a
/// space.
///
fn is_uri_autolink(body : String) -> Bool {
  let cs = chars(body)
  let colon = match body.find(":") {
    Some(c) => c
    None => return false
  }
  if colon < 2 || colon > 32 {
    return false
  }
  let s = chars(text(cs, 0, colon))
  if !s[0].is_ascii_alphabetic() {
    return false
  }
  for i in 1..<s.length() {
    let c = s[i]
    if !(c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '+' ||
      c == '-' ||
      c == '.') {
      return false
    }
  }
  true
}

///|
/// Is this the body of an email autolink?
///
/// The local part may hold the usual characters, and the domain is made of
/// labels of letters, digits and `-`, separated by `.`. A label starts and
/// ends with a letter or a digit.
///
fn is_email_autolink(body : String) -> Bool {
  let cs = chars(body)
  let at = match body.find("@") {
    Some(a) => a
    None => return false
  }
  if at == 0 {
    return false
  }
  for i in 0..<at {
    let c = cs[i]
    let ok = c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      char_in(c, ".!#$%&'*+/=?^_`{|}~-")
    if !ok {
      return false
    }
  }
  let domain = chars(text(cs, at + 1, cs.length()))
  if domain.length() == 0 {
    return false
  }
  let mut start = 0
  while start < domain.length() {
    let mut end = start
    while end < domain.length() && domain[end] != '.' {
      end += 1
    }
    if end == start {
      return false
    }
    if !is_alphanumeric(domain[start]) {
      return false
    }
    if !is_alphanumeric(domain[end - 1]) {
      return false
    }
    for i in start..<end {
      let c = domain[i]
      if !(c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-') {
        return false
      }
    }
    start = end + 1
  }
  true
}

///|
/// Scan a raw inline HTML tag, comment or declaration at `i`.
///
/// The text is raw HTML only when it follows the grammar of CommonMark, so
/// the scanners in htmltag.mbt decide what counts as a tag. What does not
/// add up stays literal text.
///
fn scan_raw_html(cs : Chars, i : Int32) -> (String, Int32)? {
  let end = html_tag_end(cs, i)
  if end < 0 {
    return None
  }
  Some((text(cs, i, end), end))
}

///|
/// The index after the raw HTML at `at`, or -1 when there is none.
///
fn html_tag_end(cs : Chars, at : Int32) -> Int32 {
  match scan_html_tag(cs, at) {
    Some((_, next)) => return next
    None => ()
  }
  match scan_html_comment(cs, at) {
    Some(next) => return next
    None => ()
  }
  match scan_cdata(cs, at) {
    Some(next) => return next
    None => ()
  }
  match scan_pi_or_declaration(cs, at) {
    Some(next) => return next
    None => ()
  }
  -1
}

///|
/// Scan a link `[label](target)` starting at the `[`.
/// Returns (label range, destination, title, index after the closing paren).
///
/// The destination and the title follow CommonMark's rules, which are
/// stricter than "everything up to the closing parenthesis":
///
///   - the destination is either written between angle brackets, where it
///     may contain spaces, or written bare, where it may not;
///   - a bare destination may not be empty, so `[a]()` is not a link, while
///     `[a](<>)` is a link with an empty destination;
///   - a title is written between `"`, `'` or `(` and `)`.
fn scan_link(
  cs : Chars,
  i : Int32,
  in_image : Bool,
) -> ((Int32, Int32), String, String, Int32)? {
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
  // a code span has a stronger claim on the backticks than a link has
  if has_backtick(cs, i + 1, label_end) {
    return None
  }
  // a link may not hold another link; an image may
  if !in_image && label_holds_link(cs, i + 1, label_end) {
    return None
  }
  let mut k = skip_link_space(cs, label_end + 2)
  // an empty destination is written as `()`
  let (dest, after_dest) = if k < cs.length() && cs[k] == ')' {
    ("", k)
  } else {
    match scan_destination(cs, k) {
      Some(x) => x
      None => return None
    }
  }
  k = skip_link_space(cs, after_dest)
  // an optional title; when there is none the destination is followed by the
  // closing parenthesis
  let mut title = ""
  let mut end = k
  match scan_title(cs, k) {
    Some((t, after_title)) => {
      title = t
      end = skip_link_space(cs, after_title)
    }
    None => ()
  }
  if end >= cs.length() || cs[end] != ')' {
    return None
  }
  Some(((i + 1, label_end), dest, title, end + 1))
}

///|
/// Scan a reference link at the `[`.
///
/// Two forms are used: `[text][label]`, where the label is given
/// explicitly, and `[label]`, where the text is the label. Both need the
/// label to be defined in the document; an undefined label stays literal
/// text.
///
/// An image may hold a link, a link may not hold one, so the caller says
/// which of the two it is.
///
fn scan_ref_link(
  cs : Chars,
  i : Int32,
  refs : Refs,
  in_image : Bool,
) -> ((Int32, Int32), String, String, Int32)? {
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
  if label_end < 0 {
    return None
  }
  // a code span has a stronger claim on the backticks than a link has
  if has_backtick(cs, i + 1, label_end) {
    return None
  }
  // a link may not hold another link; an image may
  if !in_image && label_holds_link(cs, i + 1, label_end) {
    return None
  }
  let text_label = resolve_escapes(text(cs, i + 1, label_end))
  // the explicit form: `[text][label]`
  if label_end + 1 < cs.length() && cs[label_end + 1] == '[' {
    let mut k = label_end + 2
    let mut kdepth = 1
    while k < cs.length() {
      let c = cs[k]
      if c == '\\' {
        k += 2
        continue
      }
      if c == '[' {
        kdepth += 1
      } else if c == ']' {
        kdepth -= 1
        if kdepth == 0 {
          break
        }
      }
      k += 1
    }
    if k < cs.length() {
      let inner = resolve_escapes(text(cs, label_end + 2, k))
      // the collapsed form `[text][]` names the label by the text itself
      let ref_label = if inner.is_empty() { text_label } else { inner }
      match lookup_ref(refs, ref_label) {
        Some((dest, title)) =>
          return Some(((i + 1, label_end), dest, title, k + 1))
        None =>
          // an undefined label makes the whole thing literal text
          return None
      }
    }
  }
  // the shortcut form: `[label]`
  match lookup_ref(refs, text_label) {
    Some((dest, title)) =>
      Some(((i + 1, label_end), dest, title, label_end + 1))
    None => None
  }
}

///|
/// Skip the whitespace that may sit between the parts of a link.
///
/// At most one line ending may be skipped, and a blank line ends the link.
///
fn skip_link_space(cs : Chars, k : Int32) -> Int32 {
  let mut j = k
  let mut newlines = 0
  while j < cs.length() {
    let c = cs[j]
    if c == ' ' || c == '\t' {
      j += 1
      continue
    }
    if c == '\n' {
      newlines += 1
      if newlines > 1 {
        return j
      }
      j += 1
      continue
    }
    break
  }
  j
}

///|
/// Read a link destination at `k`.
///
/// The angle bracket form `<...>` may contain spaces, which are written back
/// as `%20`. The bare form may not contain spaces or control characters, and
/// may not be empty.
///
/// The destination that comes out is the one a browser can read back: the
/// character references in it are decoded and the characters that have no
/// meaning in a URI are written as a percent sign and their hexadecimal
/// value.
///
fn scan_destination(cs : Chars, k : Int32) -> (String, Int32)? {
  if k < cs.length() && cs[k] == '<' {
    let mut j = k + 1
    let sb = StringBuilder()
    while j < cs.length() {
      let c = cs[j]
      if c == '>' {
        return Some((clean_destination(sb.to_string()), j + 1))
      }
      if c == '<' || c == '\n' {
        return None
      }
      if c == '\\' && j + 1 < cs.length() && is_punct(cs[j + 1]) {
        sb.write_char(cs[j + 1])
        j += 2
        continue
      }
      if c == ' ' {
        sb.write_string("%20")
        j += 1
        continue
      }
      sb.write_char(c)
      j += 1
    }
    return None
  }
  // the bare form
  let mut j = k
  let mut depth = 0
  let sb = StringBuilder()
  while j < cs.length() {
    let c = cs[j]
    if c == '\\' && j + 1 < cs.length() && is_punct(cs[j + 1]) {
      sb.write_char(cs[j + 1])
      j += 2
      continue
    }
    if c == '(' {
      depth += 1
      sb.write_char(c)
      j += 1
      continue
    }
    if c == ')' {
      if depth == 0 {
        break
      }
      depth -= 1
      sb.write_char(c)
      j += 1
      continue
    }
    if is_space(c) || c.to_int() < 0x20 {
      break
    }
    sb.write_char(c)
    j += 1
  }
  if depth != 0 || j == k {
    // an unbalanced parenthesis, or no destination at all
    return None
  }
  Some((clean_destination(sb.to_string()), j))
}

///|
/// The destination as a browser can read it back: the character references
/// are decoded, and the characters that have no meaning in a URI are written
/// as a percent sign and their hexadecimal value.
///
fn clean_destination(dest : String) -> String {
  encode_uri(decode_entities(dest))
}

///|
/// The text with the backslash escapes resolved.
///
/// A label is looked up with its escapes resolved, so that `[ref\[]` names the
/// same label as `[ref[]`.
///
fn resolve_escapes(s : String) -> String {
  let cs = chars(s)
  let sb = StringBuilder()
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '\\' && i + 1 < cs.length() && is_punct(cs[i + 1]) {
      sb.write_char(cs[i + 1])
      i += 2
      continue
    }
    sb.write_char(cs[i])
    i += 1
  }
  sb.to_string()
}

///|
/// Does the text between `from` and `to` hold a backtick?
///
/// A code span has a stronger claim on the backticks than a link has, so a
/// link whose text holds one is not a link at all.
///
fn has_backtick(cs : Chars, from : Int32, to : Int32) -> Bool {
  let mut i = from
  while i < to {
    if cs[i] == '`' {
      return true
    }
    i += 1
  }
  false
}

///|
/// Does the text between `from` and `to` hold a link?
///
/// A link may not hold another link: the inner one is the one that counts,
/// and the text around it stays text.
///
fn label_holds_link(cs : Chars, from : Int32, to : Int32) -> Bool {
  let mut i = from
  while i < to {
    let c = cs[i]
    if c == '\\' {
      i += 2
      continue
    }
    if c == '[' && !(i > 0 && cs[i - 1] == '!') {
      match scan_link(cs, i, false) {
        Some(_) => return true
        None => ()
      }
    }
    i += 1
  }
  false
}

///|
/// Read a link title at `k`: text between `"`, `'` or `(` and `)`.
/// Returns (title, index after the closing delimiter).
///
fn scan_title(cs : Chars, k : Int32) -> (String, Int32)? {
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
    if c == '\n' && j + 1 < cs.length() && cs[j + 1] == '\n' {
      // a blank line ends the title
      return None
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
      Link(_, _, cs) => sb.write_string(plain_text(cs))
      Image(_, alt) => sb.write_string(alt)
      RawHtml(_) => ()
      HardBreak => sb.write_string(" ")
      SoftBreak => sb.write_string(" ")
    }
  }
  sb.to_string()
}
