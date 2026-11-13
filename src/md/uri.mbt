///|
/// Percent-encoding of a URI.
///
/// A browser shows the address in the bar the way it was written, but a
/// link has to carry a destination that can be read back, so the characters
/// that have no meaning in a URI are written as a percent sign and the
/// hexadecimal value of their byte. This is what CommonMark expects of an
/// autolink.
///

///|
/// The characters that keep their meaning in a URI: the unreserved ones and
/// the reserved ones that a browser sends as they are. The percent sign is
/// one of them, so that a destination that is written as `%20` stays as it
/// is.
///
fn uri_safe_punctuation() -> String {
  ";,/?:@&=+$-_.!~*'()#%"
}

///|
/// May this character stay as it is in a URI?
///
fn is_uri_safe(c : Char) -> Bool {
  if c.is_ascii_alphabetic() || c.is_ascii_digit() {
    return true
  }
  for x in chars(uri_safe_punctuation()) {
    if x == c {
      return true
    }
  }
  false
}

///|
/// The URI with every character that may not stay as it is written as a
/// percent sign and its hexadecimal value.
///
fn encode_uri(s : String) -> String {
  let sb = StringBuilder()
  for c in chars(s) {
    let n = c.to_int()
    if n < 0x80 {
      if is_uri_safe(c) {
        sb.write_char(c)
      } else {
        write_percent(sb, n)
      }
      continue
    }
    // a character outside ASCII stands for its UTF-8 bytes
    for b in utf8_bytes(c) {
      write_percent(sb, b)
    }
  }
  sb.to_string()
}

///|
/// The UTF-8 bytes of a character.
///
fn utf8_bytes(c : Char) -> Array[Int32] {
  let n = c.to_int()
  if n < 0x80 {
    [n]
  } else if n < 0x800 {
    [0xC0 | (n >> 6), 0x80 | (n & 0x3F)]
  } else if n < 0x10000 {
    [0xE0 | (n >> 12), 0x80 | ((n >> 6) & 0x3F), 0x80 | (n & 0x3F)]
  } else {
    [
      0xF0 | (n >> 18),
      0x80 | ((n >> 12) & 0x3F),
      0x80 | ((n >> 6) & 0x3F),
      0x80 | (n & 0x3F),
    ]
  }
}

///|
/// Write one byte as a percent sign and its hexadecimal value.
///
fn write_percent(sb : StringBuilder, n : Int32) -> Unit {
  let hex = chars("0123456789ABCDEF")
  sb.write_char('%')
  sb.write_char(hex[(n >> 4) & 0xF])
  sb.write_char(hex[n & 0xF])
}
