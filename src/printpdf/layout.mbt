///|
/// The pagination maths for a printable document.

///|
/// The diagram of the actionable file is 16,302 px wide. Printed as a
/// drawing it would need thirteen A4 sheets, and the labels would end up at
/// roughly 8 px. Worse, the one finding sits at x=309 while the note that
/// explains it sits at x=11,849 - nine sheets apart, so a reader has to
/// flip back and forth to read one finding.
///
/// So the print layout does not slice the drawing. It prints
///
///   1. a KEY MAP of the whole strip: the real diagram scaled to the page
///      width, with tick marks showing where the chain, the notice fan and
///      the finding are. It is a map, not a readable drawing.
///   2. the FINDING, enlarged, cropped out of the real SVG.
///   3. the NOTICES as a list, with the footnote they all share printed
///      once instead of once per notice.
///
/// This module holds the parts of that which are pure computation: where to
/// cut, how to classify the measured geometry, and how to assemble the
/// pages. The browser measures the drawing and prints the result; it does
/// not decide anything.

///|
pub struct NodeBox {
  /// the element id, e.g. `state-f98_n0----note-8`
  id : String
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
/// A node's geometry.
///
pub fn node_box(
  id : String,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> NodeBox {
  { id, x, y, w, h, }
}

///|
/// A horizontal span of the drawing, in diagram pixels.
///
pub fn span(from : Double, to : Double) -> Span {
  { from, to, }
}

///|
/// A horizontal span of the drawing, in diagram pixels.

///|
pub struct Span {
  from : Double
  to : Double
}

///|
/// Choose crop boundaries for a wide diagram.
///
/// A hard cut at a fixed stride slices through notice boxes, so instead: find
/// the gaps between the node columns and place each boundary in the middle
/// of a gap near the ideal position. Returns ascending boundaries, first 0,
/// last `total`.
///
/// `intervals` are the horizontal extents of the nodes, in any order.
///
pub fn crop_boundaries(
  intervals : Array[Span],
  total : Double,
  target : Double,
) -> Array[Double] {
  if intervals.is_empty() {
    let out = [0.0]
    let mut x = target
    while x < total {
      out.push(x)
      x += target
    }
    out.push(total)
    return out
  }
  let sorted = intervals.copy()
  sorted.sort_by(fn(a : Span, b : Span) { a.from.compare(b.from) })
  // merge overlapping intervals into column extents
  let cols : Array[Span] = []
  for iv in sorted {
    if !cols.is_empty() {
      let last = cols[cols.length() - 1]
      if iv.from <= last.to + 30.0 {
        let merged = Span::{
          from: last.from,
          to: if iv.to > last.to {
            iv.to
          } else {
            last.to
          },
        }
        cols[cols.length() - 1] = merged
        continue
      }
    }
    cols.push(iv)
  }
  let bounds = [0.0]
  let mut next = target
  while next < total {
    // pick the gap whose midpoint is closest to the ideal cut
    let mut best = 0.0
    let mut best_d = 1.0e18
    let mut i = 0
    while i + 1 < cols.length() {
      let gap_a = cols[i].to
      let gap_b = cols[i + 1].from
      if gap_b - gap_a >= 20.0 {
        let mid = (gap_a + gap_b) / 2.0
        let d = (mid - next).abs()
        if d < best_d {
          best_d = d
          best = mid
        }
      }
      i += 1
    }
    if best_d == 1.0e18 || best <= bounds[bounds.length() - 1] + 200.0 {
      // no gap available: cut between the columns
      let mut cut = 0.0
      let mut found = false
      let mut j = 0
      while j < cols.length() {
        if cols[j].from > next {
          if j == 0 {
            cut = next
          } else {
            cut = (cols[j - 1].to + cols[j].from) / 2.0
          }
          found = true
          break
        }
        j += 1
      }
      if !found {
        cut = next
      }
      best = cut
    }
    if best <= bounds[bounds.length() - 1] {
      best = next
    }
    if best >= total {
      break
    }
    bounds.push(best)
    next = best + target
  }
  bounds.push(total)
  bounds
}

///|
/// The regions of the actionable file's diagram that the key map marks.

///|
pub struct Regions {
  /// the trust chain: scan, lexed, inspection 1/3 .. 3/3
  chain : Span
  /// the NOTICE states
  states : Span
  /// their identical footnotes
  boiler : Span
  /// the actionable finding
  defect : Span
  /// the note that explains the finding
  why : Span
  /// the x of each NOTICE state, left to right
  state_x : Array[Double]
  /// how many NOTICE states were found
  states_n : Int32
  /// how many copies of the boilerplate footnote were found
  boiler_n : Int32
}

///|
/// Classify the measured nodes of a diagram.
///
/// The classification is by IDENTITY, not by text: mermaid renders a note as
/// a node too (its id ends in `----note-N`), and the note text repeats the
/// word NOTICE - so a text match counts 27 states plus 27 note boxes.
///
pub fn classify(boxes : Array[NodeBox], file_id : String) -> Regions {
  let chain : Array[Span] = []
  let states : Array[Span] = []
  let boiler : Array[Span] = []
  let defect : Array[Span] = []
  let why : Array[Span] = []
  let state_x : Array[Double] = []
  for b in boxes {
    let id = b.id
    if id.has_prefix("state-" + file_id + "_e8----note-") {
      why.push(Span::{ from: b.x, to: b.x + b.w, })
      continue
    }
    if id.has_prefix("state-" + file_id + "_struct----note-") {
      continue
    }
    if id.has_prefix("state-" + file_id + "_n") && id.contains("----note-") {
      boiler.push(Span::{ from: b.x, to: b.x + b.w, })
      continue
    }
    if id.has_prefix("state-" + file_id + "_e8-") {
      defect.push(Span::{ from: b.x, to: b.x + b.w, })
      continue
    }
    if id.has_prefix("state-" + file_id + "_n") {
      states.push(Span::{ from: b.x, to: b.x + b.w, })
      state_x.push(b.x + b.w / 2.0)
      continue
    }
    if id.has_prefix("state-" + file_id) || id.has_prefix("state-scan-") {
      chain.push(Span::{ from: b.x, to: b.x + b.w, })
      continue
    }
  }
  let span = fn(spans : Array[Span]) -> Span {
    if spans.is_empty() {
      return Span::{ from: 0.0, to: 0.0, }
    }
    let mut lo = spans[0].from
    let mut hi = spans[0].to
    for s in spans {
      if s.from < lo {
        lo = s.from
      }
      if s.to > hi {
        hi = s.to
      }
    }
    Span::{ from: lo, to: hi, }
  }
  {
    chain: span(chain),
    states: span(states),
    boiler: span(boiler),
    defect: span(defect),
    why: span(why),
    state_x,
    states_n: state_x.length(),
    boiler_n: boiler.length(),
  }
}

///|
/// How many overview files go on one page.
///
pub const SLICE_FILES : Int32 = 12

///|
/// The groups of files that the overview is split into.
///
pub fn slice_groups(count : Int32, per_slice : Int32) -> Array[(Int32, Int32)] {
  let out : Array[(Int32, Int32)] = []
  let mut start = 0
  while start < count {
    let end = if start + per_slice < count { start + per_slice } else { count }
    out.push((start, end))
    start = end
  }
  out
}

///|
/// The source of one overview slice.
///
/// A slice is a real Mermaid diagram with the real edge labels, not a crop of
/// the overview: the overview is 1,117 x 25,160 px, and printing it whole
/// would scale it to 3 %. Twelve files per slice are readable at full size.
///
/// `direction LR` keeps the files in one column instead of a single long
/// row, and the `scan` node is declared last so that it sits at the top of
/// the column.
///
pub fn slice_source(d : @mermaid.Diagram, from : Int32, to : Int32) -> String {
  let sb = StringBuilder()
  sb.write_string("stateDiagram-v2\n    direction LR\n")
  for i in from..<to {
    let f = d.files[i]
    sb.write_string("    state \"")
    sb.write_string(f.id)
    sb.write_string(" ")
    sb.write_string(@mermaid.EM)
    sb.write_string(" ")
    sb.write_string(f.path)
    sb.write_string("\" as ")
    sb.write_string(f.id)
    sb.write_string("\n")
  }
  sb.write_string("    state \"scan ")
  sb.write_string(@mermaid.EM)
  sb.write_string(" ")
  sb.write_string(@mermaid.meta_of(d, "target"))
  sb.write_string("\" as scan\n")
  for i in from..<to {
    let f = d.files[i]
    sb.write_string("    scan --> ")
    sb.write_string(f.id)
    sb.write_string(" : ")
    sb.write_string(f.actionable.to_string())
    sb.write_string(" actionable, ")
    sb.write_string(f.notice_count.to_string())
    sb.write_string(" notice(s), parsed\n")
  }
  sb.to_string()
}
