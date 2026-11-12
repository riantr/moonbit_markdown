///|
/// The model of a Mermaid `stateDiagram-v2` scan.

///|
/// A scan is a flat list of per-file composite states hanging off one `scan`
/// node:
///
/// ```
///     scan --> f98 : 1 actionable, 27 notice(s), parsed
///     state "f98 — .repos/.../expand_v120_test.mbt" as f98 {
///         direction TB
///         [*] --> f98_lex
///         ...
///         note right of f98_n0
///             ...
///         end note
///     }
/// ```
///
/// The model keeps the raw block lines as well as the parsed states, because
/// the per-file diagram source has to be reproduced verbatim when it is
/// re-rendered on its own: that is the only way the sub-diagram stays the
/// same drawing as the original.

///|
pub struct StateDef {
  /// the state id, e.g. `f98_n0`
  id : String
  /// the state's label, e.g. `NOTICE — ParseError @77:15 — ...`
  msg : String
}

///|
pub struct NoteDef {
  /// the state the note hangs off
  owner : String
  /// the note text, with the line breaks of the source preserved as spaces
  text : String
}

///|
pub struct FileBlock {
  /// the file's state id, e.g. `f98`
  id : String
  /// the file path, taken from the composite state's label
  path : String
  /// the edge label, e.g. `1 actionable, 27 notice(s), parsed`
  edge_label : String
  /// the actionable count the edge label claims
  actionable : Int32
  /// the notice count the edge label claims
  notice_count : Int32
  /// the block's lines, verbatim
  lines : Array[String]
  /// every state declared inside the block
  states : Array[StateDef]
  /// every note inside the block
  notes : Array[NoteDef]
}

///|
pub struct Diagram {
  /// the `%% key=value` header
  meta : Array[(String, String)]
  /// the per-file blocks, in source order
  files : Array[FileBlock]
  /// the number of lines of the source the diagram was parsed from
  lines_total : Int32
}

///|
/// The em dash the generator uses in labels.
pub const EM : String = "—"

///|
/// Is this state label a NOTICE? The generator writes them as
/// `NOTICE — ParseError @77:15 — ...`.

///|
pub fn is_notice(msg : String) -> Bool {
  msg.has_prefix("NOTICE ") && msg.has_prefix("NOTICE " + EM + " ")
}

///|
/// Pipeline stages belong to the trust chain, not to the finding set.
///
pub fn is_stage(msg : String) -> Bool {
  msg == "lexed" ||
  msg.has_prefix("inspection 1/3") ||
  msg.has_prefix("inspection 2/3") ||
  msg.has_prefix("inspection 3/3")
}

///|
/// The composite state's own label (`f98 — <path>`) is not a finding.
///
pub fn is_file_label(id : String, msg : String) -> Bool {
  msg.has_prefix(id + " " + EM + " ")
}

///|
/// The number of actionable findings the diagram actually draws.
///
pub fn drawn_findings(d : Diagram) -> Int32 {
  let mut n = 0
  for f in d.files {
    for s in f.states {
      if !is_notice(s.msg) && !is_stage(s.msg) && !is_file_label(f.id, s.msg) {
        n += 1
      }
    }
  }
  n
}

///|
/// The number of NOTICE states the diagram actually draws.
///
pub fn drawn_notices(d : Diagram) -> Int32 {
  let mut n = 0
  for f in d.files {
    for s in f.states {
      if is_notice(s.msg) {
        n += 1
      }
    }
  }
  n
}

///|
/// The number of notes the diagram actually draws.
///
pub fn drawn_notes(d : Diagram) -> Int32 {
  let mut n = 0
  for f in d.files {
    n += f.notes.length()
  }
  n
}

///|
/// The number of NOTICE states of one file.
///
pub fn drawn_file_notices(f : FileBlock) -> Int32 {
  let mut n = 0
  for s in f.states {
    if is_notice(s.msg) {
      n += 1
    }
  }
  n
}

///|
/// The number of actionable findings of one file.
///
pub fn drawn_file_findings(f : FileBlock) -> Int32 {
  let mut n = 0
  for s in f.states {
    if !is_notice(s.msg) && !is_stage(s.msg) && !is_file_label(f.id, s.msg) {
      n += 1
    }
  }
  n
}

///|
/// The metadata value for `key`, or the empty string.
///
pub fn meta_of(d : Diagram, key : String) -> String {
  for (k, v) in d.meta {
    if k == key {
      return v
    }
  }
  ""
}
