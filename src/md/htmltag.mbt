///|
/// The HTML tag grammar of CommonMark.
///
/// Text between `<` and `>` is raw HTML only when it follows this grammar.
/// The rules are strict: an illegal attribute name or an unterminated
/// attribute value makes the whole tag literal text. So every part of a tag
/// has to be checked, and a tag that does not add up is not a tag at all.
///
/// A tag may hold one line ending, the way an attribute list may be broken
/// over two lines; a second line ending ends it.
///

///|
/// Skip spaces, tabs and at most one line ending.
///
/// CommonMark allows a single line ending inside a tag, so a second one ends
/// the run of whitespace.
///
fn skip_tag_space(cs : Chars, at : Int32) -> Int32 {
  let mut j = at
  let mut newline = false
  while j < cs.length() {
    let c = cs[j]
    if c == ' ' || c == '\t' {
      j += 1
      continue
    }
    if c == '\n' || c == '\r' {
      if newline {
        break
      }
      newline = true
      j += 1
      if c == '\r' && j < cs.length() && cs[j] == '\n' {
        j += 1
      }
      continue
    }
    break
  }
  j
}

///|
/// Can a tag name start with this character? A tag name is a letter,
/// followed by letters, digits or hyphens.
///
fn is_tag_name_start(c : Char) -> Bool {
  c.is_ascii_alphabetic()
}

///|
/// Can a tag name carry on with this character?
///
fn is_tag_name_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-'
}

///|
/// Can an attribute name start with this character? An attribute name is a
/// letter, an underscore or a colon, followed by letters, digits,
/// underscores, dots, colons or hyphens.
///
fn is_attr_name_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_' || c == ':'
}

///|
/// Can an attribute name carry on with this character?
///
fn is_attr_name_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  c == '_' ||
  c == '.' ||
  c == ':' ||
  c == '-'
}

///|
/// The index after the attribute value that starts at `at`, or None when
/// there is no value there.
///
/// A value in quotes ends at the matching quote, and a value without quotes
/// ends at the first space, tab, line ending, quote, `=`, `<`, `>` or
/// backtick. A quoted value has no escape: a backslash is just a character.
///
fn scan_attr_value(cs : Chars, at : Int32) -> Int32? {
  if at >= cs.length() {
    return None
  }
  let quote = cs[at]
  if quote == '"' || quote == '\'' {
    let mut j = at + 1
    while j < cs.length() && cs[j] != quote {
      j += 1
    }
    if j >= cs.length() {
      return None
    }
    return Some(j + 1)
  }
  let mut j = at
  while j < cs.length() {
    let c = cs[j]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      break
    }
    if c == '"' || c == '\'' || c == '=' || c == '<' || c == '>' || c == '`' {
      break
    }
    j += 1
  }
  if j == at {
    return None
  }
  Some(j)
}

///|
/// The name of the tag and the index after it, or None when there is no
/// complete tag at `at`.
///
/// Both the open tag and the closing tag are recognised; a closing tag may
/// not hold attributes.
///
fn scan_html_tag(cs : Chars, at : Int32) -> (String, Int32)? {
  if at >= cs.length() || cs[at] != '<' {
    return None
  }
  let mut j = at + 1
  let closing = j < cs.length() && cs[j] == '/'
  if closing {
    j += 1
  }
  if j >= cs.length() || !is_tag_name_start(cs[j]) {
    return None
  }
  let name_start = j
  j += 1
  while j < cs.length() && is_tag_name_char(cs[j]) {
    j += 1
  }
  let name = text(cs, name_start, j)
  if closing {
    let k = skip_tag_space(cs, j)
    if k < cs.length() && cs[k] == '>' {
      return Some((name, k + 1))
    }
    return None
  }
  match scan_open_tag(cs, j) {
    Some(end) => Some((name, end))
    None => None
  }
}

///|
/// The index after the open tag whose attributes start at `at`, or None when
/// the tag does not add up.
///
/// The tag is a name, then attributes, then the `>`. Every attribute needs
/// whitespace in front of it, and the whitespace may hold one line ending.
///
fn scan_open_tag(cs : Chars, at : Int32) -> Int32? {
  let mut j = at
  let mut end = -1
  while end < 0 {
    let k = skip_tag_space(cs, j)
    if k > j && k < cs.length() && is_attr_name_start(cs[k]) {
      // the attribute name
      let mut m = k + 1
      while m < cs.length() && is_attr_name_char(cs[m]) {
        m += 1
      }
      // the optional value
      let v = skip_tag_space(cs, m)
      if v < cs.length() && cs[v] == '=' {
        let w = skip_tag_space(cs, v + 1)
        match scan_attr_value(cs, w) {
          Some(x) => {
            j = x
            continue
          }
          None => return None
        }
      }
      j = m
      continue
    }
    // no more attributes: the tag ends here
    j = k
    if j < cs.length() && cs[j] == '/' {
      j += 1
    }
    if j < cs.length() && cs[j] == '>' {
      end = j + 1
    } else {
      return None
    }
  }
  Some(end)
}

///|
/// The index after the HTML comment that starts at `at`, or None.
///
/// `<!-->` and `<!--->` are comments on their own; every other comment runs
/// to the first `-->`.
///
fn scan_html_comment(cs : Chars, at : Int32) -> Int32? {
  if !has_at(cs, at, "<!--") {
    return None
  }
  if has_at(cs, at, "<!-->") {
    return Some(at + 5)
  }
  if has_at(cs, at, "<!--->") {
    return Some(at + 6)
  }
  let mut j = at + 4
  while j + 2 < cs.length() {
    if cs[j] == '-' && cs[j + 1] == '-' && cs[j + 2] == '>' {
      return Some(j + 3)
    }
    j += 1
  }
  None
}

///|
/// The index after the CDATA section that starts at `at`, or None.
///
fn scan_cdata(cs : Chars, at : Int32) -> Int32? {
  if !has_at(cs, at, "<![CDATA[") {
    return None
  }
  let mut j = at + 9
  while j + 2 < cs.length() {
    if cs[j] == ']' && cs[j + 1] == ']' && cs[j + 2] == '>' {
      return Some(j + 3)
    }
    j += 1
  }
  None
}

///|
/// The index after the processing instruction or the declaration that
/// starts at `at`, or None.
///
/// A processing instruction runs to the first `?>`; a declaration is a
/// letter after `<!` and runs to the first `>`.
///
fn scan_pi_or_declaration(cs : Chars, at : Int32) -> Int32? {
  if has_at(cs, at, "<?") {
    let mut j = at + 2
    while j + 1 < cs.length() {
      if cs[j] == '?' && cs[j + 1] == '>' {
        return Some(j + 2)
      }
      j += 1
    }
    return None
  }
  if at + 2 < cs.length() &&
    cs[at + 1] == '!' &&
    cs[at + 2].is_ascii_alphabetic() {
    let mut j = at + 2
    while j < cs.length() && cs[j] != '>' {
      j += 1
    }
    if j < cs.length() {
      return Some(j + 1)
    }
  }
  None
}

///|
/// Does the text at `at` start with `word`?
///
fn has_at(cs : Chars, at : Int32, word : String) -> Bool {
  let w = chars(word)
  if at + w.length() > cs.length() {
    return false
  }
  for k in 0..<w.length() {
    if cs[at + k] != w[k] {
      return false
    }
  }
  true
}

///|
/// Does the text hold `needle`? The needle has to be lower case already and
/// the text is lowered before the search, so the comparison ignores the case
/// of ASCII letters.
///
fn contains_text(s : String, needle : String) -> Bool {
  let cs = chars(s.to_lower())
  let n = chars(needle)
  if n.length() == 0 {
    return true
  }
  let mut i = 0
  while i + n.length() <= cs.length() {
    let mut k = 0
    while k < n.length() && cs[i + k] == n[k] {
      k += 1
    }
    if k == n.length() {
      return true
    }
    i += 1
  }
  false
}
