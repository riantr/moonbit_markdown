///|
/// Decode the HTML character references in `s`.
///
/// A Markdown document may write `&amp;` or `&#233;` instead of the character
/// itself. The browser has to show the character, so the reference is
/// decoded here, before the text reaches the HTML renderer - which escapes
/// `&` again on the way out, so `&amp;` survives the round trip and
/// `&copy;` becomes a real ©.
///
/// A reference that is not in the HTML5 list is left alone: `&MadeUp;` is
/// literal text, not an error.

///|
fn decode_entities(s : String) -> String {
  let cs = chars(s)
  let sb = StringBuilder()
  let mut i = 0
  while i < cs.length() {
    if cs[i] != '&' {
      sb.write_char(cs[i])
      i += 1
      continue
    }
    match scan_entity(cs, i) {
      Some((value, next)) => {
        sb.write_string(value)
        i = next
        continue
      }
      None => ()
    }
    sb.write_char('&')
    i += 1
  }
  sb.to_string()
}

///|
/// The character reference at `i`, decoded, and the index after it.
///
/// Returns None when there is no reference there, so that the text is left
/// as it was. The reference is decoded where it stands, which matters for
/// the text that follows a backslash escape: `\&ouml;` is an escaped
/// ampersand and not the character ö.
///
fn scan_entity(cs : Chars, i : Int32) -> (String, Int32)? {
  if i >= cs.length() || cs[i] != '&' {
    return None
  }
  // the name runs to the first `;`, and it may not be longer than 32
  // characters; anything else is not a reference
  let mut j = i + 1
  let name = StringBuilder()
  while j < cs.length() && cs[j] != ';' && j - i <= 33 {
    name.write_char(cs[j])
    j += 1
  }
  if j >= cs.length() || cs[j] != ';' {
    return None
  }
  let n = name.to_string()
  if n.is_empty() {
    return None
  }
  let sb = StringBuilder()
  if n.length() > 1 && n[0] == '#' {
    if !decode_numeric(n, sb) {
      return None
    }
  } else {
    match entity_value(n) {
      Some(v) => sb.write_string(v)
      None => return None
    }
  }
  Some((sb.to_string(), j + 1))
}

///|
/// The value of a digit in the given radix, or -1 when the character is not
/// a digit of that radix.
///
fn digit_value(c : Char) -> Int32 {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 97 && v <= 102 {
    v - 87
  } else if v >= 65 && v <= 70 {
    v - 55
  } else {
    -1
  }
}

///|
/// Decode a numeric reference such as `&#233;` or `&#x1F600;`.
/// Returns false when the number is not one, in which case nothing is
/// written and the text is left as it was.
///
fn decode_numeric(name : String, sb : StringBuilder) -> Bool {
  let cs = chars(name)
  let mut i = 1
  let radix = if i < cs.length() && (cs[i] == 'x' || cs[i] == 'X') {
    i += 1
    16
  } else {
    10
  }
  if i >= cs.length() {
    return false
  }
  let mut value = 0
  while i < cs.length() {
    let n = digit_value(cs[i])
    if n < 0 || n >= radix {
      return false
    }
    value = value * radix + n
    i += 1
  }
  // the HTML5 range: 0, and the Unicode planes, with the surrogates and the
  // non-characters left out
  if value == 0 {
    // the null character stands for the replacement character
    match Int::to_char(0xfffd) {
      Some(c) => {
        sb.write_char(c)
        true
      }
      None => false
    }
  } else if value > 0x10ffff {
    false
  } else if value >= 0xd800 && value <= 0xdfff {
    false
  } else {
    match Int::to_char(value) {
      Some(c) => {
        sb.write_char(c)
        true
      }
      None => false
    }
  }
}
