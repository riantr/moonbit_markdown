///|
/// Number formatting for the printed document.

///|
/// The print layout is full of numbers that come out of the browser's
/// geometry: pixel positions, scales, page counts, distances. They are
/// written the way the reference implementation wrote them - one decimal for
/// positions, whole numbers for counts, thousands separators for the big
/// ones - so that the two documents can be compared number by number.

///|

///|
/// One decimal place, like JavaScript's `toFixed(1)`.
///
pub fn fmt1(x : Double) -> String {
  let neg = x < 0.0
  let v = if neg { -x } else { x }
  let t = (v * 10.0).round().to_int()
  let whole = t / 10
  let frac = t % 10
  let sign = if neg { "-" } else { "" }
  sign + whole.to_string() + "." + frac.to_string()
}

///|
/// A whole number, rounded, like JavaScript's `Math.round`.
///
pub fn fmt0(x : Double) -> String {
  x.round().to_int().to_string()
}

///|
/// A whole number with thousands separators, like `toLocaleString('en-US')`.
///
pub fn group(n : Int32) -> String {
  let s = n.to_string()
  let neg = s.has_prefix("-")
  let digits = if neg { s[1:s.length()].to_owned() } else { s }
  let cs = @text.chars(digits)
  let sb = StringBuilder()
  if neg {
    sb.write_string("-")
  }
  let mut i = 0
  while i < cs.length() {
    let rest = cs.length() - i
    if i > 0 && rest % 3 == 0 {
      sb.write_string(",")
    }
    sb.write_char(cs[i])
    i += 1
  }
  sb.to_string()
}

///|
/// The value of a decimal number written in text.
///
/// The browser writes numbers with JavaScript's shortest round-trip form, so
/// the text can be `16302`, `1819.5` or `0.30000000000000004`. This reads
/// that back without raising, which the core library's parser would.
///
pub fn parse_num(s : String) -> Double {
  let cs = @text.chars(s)
  let mut i = 0
  let mut neg = false
  if i < cs.length() && (cs[i] == '-' || cs[i] == '+') {
    neg = cs[i] == '-'
    i += 1
  }
  let mut whole = 0.0
  while i < cs.length() && cs[i].is_ascii_digit() {
    whole = whole * 10.0 + (cs[i].to_int() - 48).to_double()
    i += 1
  }
  let mut value = whole
  if i < cs.length() && cs[i] == '.' {
    i += 1
    let mut scale = 0.1
    while i < cs.length() && cs[i].is_ascii_digit() {
      value = value + (cs[i].to_int() - 48).to_double() * scale
      scale = scale * 0.1
      i += 1
    }
  }
  if neg {
    -value
  } else {
    value
  }
}
