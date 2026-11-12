///|
/// Markdown specific text helpers, and the re-export of the generic ones.
///
/// The generic character helpers live in `riantr/moonbit_markdown/src/text`,
/// because the Mermaid and print packages need them too and must not depend
/// on the Markdown package. They are re-exported here so that the Markdown
/// sources can use them unqualified.
///

///|
/// The character array the generic helpers work on.
///
pub type Chars = Array[Char]

///|
pub using @tx {
  chars,
  text,
  slice,
  is_space,
  is_punct,
  trim_range,
  trimmed,
  ltrim,
  split_lines,
  leading_spaces,
}

///|
/// The first word of `s`, or the whole string when it has no space.
///
pub fn first_word(s : String) -> String {
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && !is_space(cs[i]) {
    i += 1
  }
  text(cs, 0, i)
}
