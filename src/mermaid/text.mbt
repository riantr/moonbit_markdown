///|
/// Re-export of the generic character helpers, so that the Mermaid sources
/// can use them unqualified without depending on the Markdown package.
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
