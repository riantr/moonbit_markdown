///|
/// The focused source of one file's diagram.

///|
/// The 27 NOTICE states of the actionable file each carry the SAME
/// boilerplate footnote - a 230 x 294 px box with identical text, printed 27
/// times side by side. That is what made the diagram 16,302 px wide, and
/// slicing it across pages left every label at roughly 8 px.
///
/// The focused source keeps the substance of the drawing - the trust chain,
/// the file-level note, the actionable finding and its WHY note - and drops
/// only the 27 duplicated footnotes and the 27 states they hang off. Every
/// other node and every other edge stays. The dropped footnote is printed
/// once, as a legend next to the notice list.

///|
/// The reference implementation did this in the PDF builder; here it is a
/// pure function of the parsed model, so it can be tested on its own.

///|

///|
/// The owner of a `note right of <owner>` line, or None when the line is
/// not the start of a note.
///
fn note_owner_of(line : String) -> String? {
  let t = @text.trimmed(@text.chars(line))
  let prefix = "note right of "
  if !t.has_prefix(prefix) {
    return None
  }
  let cs = @text.chars(t[prefix.length():t.length()].to_owned())
  let mut end = 0
  while end < cs.length() && !@text.is_space(cs[end]) {
    end += 1
  }
  if end == 0 {
    return None
  }
  Some(@text.text(cs, 0, end))
}

///|
/// Is this the id of one of the NOTICE states, i.e. `<file>_n<number>`?
///
fn is_fan_state(file_id : String, owner : String) -> Bool {
  let prefix = file_id + "_n"
  if !owner.has_prefix(prefix) {
    return false
  }
  let cs = @text.chars(owner)
  let mut i = prefix.length()
  if i >= cs.length() {
    return false
  }
  while i < cs.length() {
    if !cs[i].is_ascii_digit() {
      return false
    }
    i += 1
  }
  true
}

///|
/// Does this line mention one of the NOTICE states?
///
/// The reference implementation dropped a line when it matched
/// `/f98_n\d+/` anywhere in it, which also drops the edges that lead into
/// the notice fan - that is the point: the fan leaves the drawing.
///
fn mentions_fan_state(file_id : String, line : String) -> Bool {
  let needle = @text.chars(file_id + "_n")
  let cs = @text.chars(line)
  let nl = needle.length()
  let mut i = 0
  while i + nl < cs.length() {
    let mut hit = true
    let mut k = 0
    while k < nl {
      if cs[i + k] != needle[k] {
        hit = false
        break
      }
      k += 1
    }
    if hit && cs[i + nl].is_ascii_digit() {
      return true
    }
    i += 1
  }
  false
}

///|
/// The focused source of one file's diagram: the block's own lines, with the
/// notice fan and its duplicated footnotes removed.
///
pub fn focus_source(f : @mermaid.FileBlock) -> String {
  let out : Array[String] = []
  let mut in_note = false
  let mut keep_note = false
  for line in f.lines {
    match note_owner_of(line) {
      Some(owner) => {
        in_note = true
        keep_note = !is_fan_state(f.id, owner)
        if keep_note {
          out.push(line)
        }
        continue
      }
      None => ()
    }
    if in_note {
      if @text.trimmed(@text.chars(line)) == "end note" {
        in_note = false
        if keep_note {
          out.push(line)
        }
      } else if keep_note {
        out.push(line)
      }
      continue
    }
    if mentions_fan_state(f.id, line) {
      continue
    }
    out.push(line)
  }
  let sb = StringBuilder()
  sb.write_string("stateDiagram-v2\n    direction TB\n")
  for line in out {
    sb.write_string(line)
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// The boilerplate footnote of the notice fan, printed once.
///
/// It is the text of the first note that hangs off a NOTICE state. Every one
/// of the 27 notes is a copy of it, so the first is enough.
///
pub fn fan_boilerplate(f : @mermaid.FileBlock) -> String {
  let mut in_note = false
  let buf : Array[String] = []
  for line in f.lines {
    if in_note {
      if @text.trimmed(@text.chars(line)) == "end note" {
        in_note = false
        break
      }
      buf.push(@text.trimmed(@text.chars(line)))
      continue
    }
    match note_owner_of(line) {
      Some(owner) => if is_fan_state(f.id, owner) { in_note = true }
      None => ()
    }
  }
  buf.join(" ")
}
