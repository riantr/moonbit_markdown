///|
/// Text helpers shared by the Markdown, Mermaid and print packages.

///|
/// MoonBit's `String` is UTF-16: `s[i]` yields a `UInt16` code unit and
/// `s.length()` counts code units, not characters. Slicing at a code unit
/// boundary can therefore cut a surrogate pair in half, which turns one
/// character into two broken ones. Everything here that reasons about
/// characters works on `Array[Char]` instead, obtained with
/// `String::to_array`; indices are then character indices and no slice can
/// split a surrogate pair.

///|
pub type Chars = Array[Char]

///|
pub fn chars(s : String) -> Chars {
  s.to_array()
}

///|
/// The text of `cs[from..to]`.
///
pub fn text(cs : Chars, from : Int32, to : Int32) -> String {
  let sb = StringBuilder()
  let mut i = from
  while i < to {
    sb.write_char(cs[i])
    i += 1
  }
  sb.to_string()
}

///|
pub fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
pub fn is_punct(c : Char) -> Bool {
  match c {
    '!'
    | '"'
    | '#'
    | '$'
    | '%'
    | '&'
    | '\''
    | '('
    | ')'
    | '*'
    | '+'
    | ','
    | '-'
    | '.'
    | '/'
    | ':'
    | ';'
    | '<'
    | '='
    | '>'
    | '?'
    | '@'
    | '['
    | '\\'
    | ']'
    | '^'
    | '_'
    | '`'
    | '{'
    | '|'
    | '}'
    | '~' => true
    _ => false
  }
}

///|
/// The range of `cs` with leading and trailing whitespace removed.
/// Returns (from, to); an all-whitespace input gives an empty range.
///
pub fn trim_range(cs : Chars) -> (Int32, Int32) {
  let mut a = 0
  let mut b = cs.length()
  while a < b && is_space(cs[a]) {
    a += 1
  }
  while b > a && is_space(cs[b - 1]) {
    b -= 1
  }
  (a, b)
}

///|
/// The trimmed text of `cs`.
///
pub fn trimmed(cs : Chars) -> String {
  let (a, b) = trim_range(cs)
  text(cs, a, b)
}

///|
/// The text of `cs` with leading whitespace removed, but trailing whitespace
/// kept. Trailing spaces matter: two of them at the end of a line make a
/// hard line break.
///
pub fn ltrim(cs : Chars) -> String {
  let mut a = 0
  while a < cs.length() && is_space(cs[a]) {
    a += 1
  }
  text(cs, a, cs.length())
}

///|
/// Split a string into lines. Handles LF, CRLF and CR, and does not keep a
/// trailing empty line for a trailing newline.
///
pub fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let cs = chars(s)
  let mut start = 0
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '\n' {
      out.push(text(cs, start, i))
      i += 1
      start = i
      continue
    }
    if cs[i] == '\r' {
      out.push(text(cs, start, i))
      i += 1
      if i < cs.length() && cs[i] == '\n' {
        i += 1
      }
      start = i
      continue
    }
    i += 1
  }
  if start < cs.length() {
    out.push(text(cs, start, cs.length()))
  }
  out
}

///|
/// The characters of `s` from `from` to `to`.
///
/// The indices are CHARACTER indices. A string slice counts UTF-16 code
/// units, so it cuts a surrogate pair in half; this works on the decoded
/// characters and cannot. `from` and `to` are clamped to the string.
///
pub fn slice(s : String, from : Int32, to : Int32) -> String {
  let cs = chars(s)
  let a = if from < 0 { 0 } else { from }
  let b = if to > cs.length() { cs.length() } else { to }
  if a >= b {
    return ""
  }
  text(cs, a, b)
}

///|
/// The number of leading spaces of a line.
///
pub fn leading_spaces(s : String) -> Int32 {
  let cs = chars(s)
  let mut n = 0
  while n < cs.length() && cs[n] == ' ' {
    n += 1
  }
  n
}
