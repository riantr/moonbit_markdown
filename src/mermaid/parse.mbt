///|
/// Parsing a Mermaid `stateDiagram-v2` scan into the model.

///|
/// The generator's output has a fixed shape, which is what this parser
/// relies on:
///
///   - a `%%` header whose lines pack several `key=value` pairs together;
///   - one `scan --> fN : <label>` edge per file, each followed by the
///     file's composite state, indented by four spaces;
///   - inside a composite state, `state "..." as id` declarations and
///     `note right of id` ... `end note` blocks.
///
/// Everything the parser does not recognise is kept in the block's raw lines,
/// so re-rendering a sub-diagram reproduces the source exactly.

///|
fn strip_prefix(s : String, prefix : String) -> String? {
  if s.has_prefix(prefix) {
    Some(s[prefix.length():s.length()].to_owned())
  } else {
    None
  }
}

///|
/// Parse the `%%` header. One line may carry several `key=value` pairs, so
/// the body is split on whitespace first and each piece is read as a pair.
/// The first occurrence of a key wins, which is what the reference
/// implementation did.
///
fn parse_meta(lines : Array[String]) -> Array[(String, String)] {
  let meta : Array[(String, String)] = []
  for line in lines {
    let t = trimmed(chars(line))
    if !t.has_prefix("%%") {
      continue
    }
    let body = trimmed(chars(t[2:t.length()].to_owned()))
    for piece in split_lines(body.replace_all(old=" ", new="\n")) {
      if piece.is_empty() {
        continue
      }
      match piece.find("=") {
        Some(i) => {
          let k = piece[0:i].to_owned()
          let v = piece[i + 1:piece.length()].to_owned()
          let mut seen = false
          for (ek, _) in meta {
            if ek == k {
              seen = true
            }
          }
          if !seen {
            meta.push((k, v))
          }
        }
        None => ()
      }
    }
  }
  meta
}

///|
/// Is this line the start of a per-file block (`scan --> fN : ...`)?
/// Returns the file id when it is.
///
fn scan_edge_id(line : String) -> String? {
  if leading_spaces(line) != 4 {
    return None
  }
  let t = trimmed(chars(line))
  if !t.has_prefix("scan --> ") {
    return None
  }
  let rest = t[9:t.length()].to_owned()
  let mut end = 0
  let rc = chars(rest)
  while end < rc.length() && rc[end] != ' ' && rc[end] != ':' {
    end += 1
  }
  let id = rest[0:end].to_owned()
  if id.length() > 1 && id[0] == 'f' && id[1:].all(fn(c) { c.is_ascii_digit() }) {
    Some(id)
  } else {
    None
  }
}

///|
/// The label of the `scan --> fN` edge, i.e. everything after the colon.
///
fn edge_label_of(line : String) -> String {
  let t = trimmed(chars(line))
  match t.find(": ") {
    Some(i) => t[i + 2:t.length()].to_owned()
    None => ""
  }
}

///|
/// The number in `N actionable`, or 0.
///
fn count_before(label : String, word : String) -> Int32 {
  let cs = chars(label)
  let mut i = 0
  while i < cs.length() {
    if cs[i].is_ascii_digit() {
      let start = i
      while i < cs.length() && cs[i].is_ascii_digit() {
        i += 1
      }
      let num = slice(label, start, i)
      let rest = trimmed(chars(slice(label, i, cs.length())))
      if rest.has_prefix(word) {
        return digits_to_int(num)
      }
      continue
    }
    i += 1
  }
  0
}

///|
/// Parse one file block: the composite state, its states and its notes.
///
fn parse_file_block(
  id : String,
  label : String,
  lines : Array[String],
) -> FileBlock {
  let path = file_path_of(id, lines)
  let states : Array[StateDef] = []
  let notes : Array[NoteDef] = []
  let mut in_note = false
  let mut note_owner = ""
  let mut note_buf : Array[String] = []
  for line in lines {
    if in_note {
      if trimmed(chars(line)) == "end note" {
        notes.push({ owner: note_owner, text: note_buf.join(" "), })
        note_buf = []
        in_note = false
        continue
      }
      note_buf.push(trimmed(chars(line)))
      continue
    }
    let t = trimmed(chars(line))
    match strip_prefix(t, "note right of ") {
      Some(owner) => {
        in_note = true
        note_owner = owner
        note_buf = []
        continue
      }
      None => ()
    }
    match state_decl(t) {
      Some((sid, msg)) => states.push({ id: sid, msg, })
      None => ()
    }
  }
  {
    id,
    path,
    edge_label: label,
    actionable: count_before(label, "actionable"),
    notice_count: count_before(label, "notice(s)"),
    lines,
    states,
    notes,
  }
}

///|
/// The composite state's label is `fN — <path>`; the path is what follows
/// the em dash.
///
fn file_path_of(id : String, lines : Array[String]) -> String {
  let prefix = "state \"" + id + " " + EM + " "
  for line in lines {
    let t = trimmed(chars(line))
    if t.has_prefix(prefix) {
      let rest = t[prefix.length():t.length()].to_owned()
      match rest.find("\" as ") {
        Some(i) => return rest[0:i].to_owned()
        None => return rest
      }
    }
  }
  ""
}

///|
/// A state declaration: `state "..." as id`.
/// Returns (id, message).
///
fn state_decl(t : String) -> (String, String)? {
  if !t.has_prefix("state \"") {
    return None
  }
  let cs = chars(t)
  let mut first = -1
  let mut last = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '"' {
      if first < 0 {
        first = i
      } else {
        last = i
      }
    }
    i += 1
  }
  if first < 0 || last <= first {
    return None
  }
  let msg = text(cs, first + 1, last)
  let rest = slice(t, last + 1, cs.length())
  if !rest.has_prefix(" as ") {
    return None
  }
  let id = trimmed(chars(slice(rest, 4, chars(rest).length())))
  // a declaration names one state and nothing else; the composite state's
  // own header (`state "f1 — path" as f1 {`) is not a state
  if id.is_empty() {
    return None
  }
  let idc = chars(id)
  for ch in idc.iter() {
    if !(ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_') {
      return None
    }
  }
  Some((id, msg))
}

///|
/// Parse a whole scan file.
///
pub fn parse_diagram(src : String) -> Diagram {
  let lines = split_lines(src)
  let meta = parse_meta(lines)
  let files : Array[FileBlock] = []
  let mut i = 0
  while i < lines.length() {
    match scan_edge_id(lines[i]) {
      Some(id) => {
        let label = edge_label_of(lines[i])
        let block : Array[String] = [lines[i]]
        let mut j = i + 1
        while j < lines.length() {
          block.push(lines[j])
          let done = trimmed(chars(lines[j])) == "}" &&
            leading_spaces(lines[j]) == 4
          j += 1
          if done {
            break
          }
        }
        files.push(parse_file_block(id, label, block))
        i = j
        continue
      }
      None => ()
    }
    i += 1
  }
  { meta, files, lines_total: lines.length(), }
}

///|
/// The value of a run of decimal digits.
///
fn digits_to_int(s : String) -> Int32 {
  let cs = chars(s)
  let mut n = 0
  let mut i = 0
  while i < cs.length() && cs[i].is_ascii_digit() {
    n = n * 10 + (cs[i].to_int() - 48)
    i += 1
  }
  n
}
