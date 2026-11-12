///|
/// Tests for the text helpers.
///
/// The point of this package is that it never cuts a character in half, so
/// most of these tests are about the character count and the slicing, not
/// about the trimming.

///|
test "characters are counted, not code units" {
  // a string is a run of UTF-16 code units, so a character outside the basic
  // plane takes two of them
  @test.assert_eq("a🌙b".length(), 4)
  @test.assert_eq(@text.chars("a🌙b").length(), 3)
  // "é" is inside the basic plane: one unit, one character
  @test.assert_eq("héllo".length(), 5)
  @test.assert_eq(@text.chars("héllo").length(), 5)
}

///|
test "a slice never cuts a surrogate pair in half" {
  let cs = @text.chars("héllo")
  @test.assert_eq(@text.text(cs, 0, 2), "hé")
  @test.assert_eq(@text.text(cs, 0, 5), "héllo")
  @test.assert_eq(@text.text(cs, 3, 5), "lo")
  @test.assert_eq(@text.text(cs, 1, 1), "")
  // the same, through the string slice: it is indexed by character too
  @test.assert_eq("héllo"[0:2].to_owned(), "hé")
}

///|
test "the slice helper works in characters" {
  @test.assert_eq(@text.slice("a🌙b", 0, 3), "a🌙b")
  @test.assert_eq(@text.slice("a🌙b", 1, 2), "🌙")
  @test.assert_eq(@text.slice("a🌙b", 0, 1), "a")
  // out of range is clamped, not an error
  @test.assert_eq(@text.slice("a🌙b", 0, 99), "a🌙b")
  @test.assert_eq(@text.slice("a🌙b", 9, 99), "")
  @test.assert_eq(@text.slice("a🌙b", -3, 1), "a")
}

///|
test "trimming takes the whitespace off both ends" {
  @test.assert_eq(@text.trimmed(@text.chars("  hello  ")), "hello")
  @test.assert_eq(@text.trimmed(@text.chars("\t\nhello\r\n")), "hello")
  @test.assert_eq(@text.trimmed(@text.chars("   ")), "")
  @test.assert_eq(@text.trimmed(@text.chars("hello")), "hello")
  @test.assert_eq(@text.trim_range(@text.chars("  hello  ")), (2, 7))
  @test.assert_eq(@text.trim_range(@text.chars("   ")), (3, 3))
}

///|
test "ltrim keeps the trailing spaces, because they mean a line break" {
  @test.assert_eq(@text.ltrim(@text.chars("  hello  ")), "hello  ")
  @test.assert_eq(@text.ltrim(@text.chars("hello")), "hello")
}

///|
test "lines are split on LF, CRLF and CR" {
  @test.assert_eq(@text.split_lines("a\nb\nc"), ["a", "b", "c"])
  @test.assert_eq(@text.split_lines("a\r\nb\r\nc"), ["a", "b", "c"])
  @test.assert_eq(@text.split_lines("a\rb\rc"), ["a", "b", "c"])
  // a trailing newline does not make an empty last line
  @test.assert_eq(@text.split_lines("a\n"), ["a"])
  @test.assert_eq(@text.split_lines(""), [])
  @test.assert_eq(@text.split_lines("a\n\nb"), ["a", "", "b"])
}

///|
test "the leading spaces of a line are counted" {
  @test.assert_eq(@text.leading_spaces("    state \"x\""), 4)
  @test.assert_eq(@text.leading_spaces("state \"x\""), 0)
  @test.assert_eq(@text.leading_spaces("   \tx"), 3)
}

///|
test "spaces and punctuation are told apart" {
  @test.assert_eq(@text.is_space(' '), true)
  @test.assert_eq(@text.is_space('\t'), true)
  @test.assert_eq(@text.is_space('a'), false)
  @test.assert_eq(@text.is_punct('.'), true)
  @test.assert_eq(@text.is_punct('-'), true)
  @test.assert_eq(@text.is_punct('a'), false)
  @test.assert_eq(@text.is_punct('0'), false)
}
