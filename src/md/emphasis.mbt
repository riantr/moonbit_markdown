///|
/// Emphasis and strong emphasis, resolved the way CommonMark resolves them:
/// with a delimiter stack.
///
/// The naive rule - a run of `*` or `_` that may open starts an emphasis,
/// the next run of the same character that may close ends it - gives the
/// wrong answer whenever two runs overlap or nest. The specification keeps
/// every delimiter run on a stack and resolves the stack from left to right,
/// and that is what makes `*foo **bar** baz*` an emphasis containing a
/// strong emphasis, `***foo***` an emphasis containing a strong emphasis
/// rather than three literal asterisks, and `*foo**bar*` an emphasis with
/// two literal asterisks inside it.
///
/// The algorithm is the reference implementation's, and it is worth stating
/// because the rules interact:
///
/// - a run may open and a run may close, and the two are decided by the
///   flanking rules (see `scan_delim`);
/// - a closer looks back for an opener of the same character, and the
///   nearest one wins, unless the "rule of three" forbids the pair - two
///   runs whose lengths add up to a multiple of three may not match if one
///   of them could also be used the other way round;
/// - a run of two or more characters gives strong emphasis, and a run of
///   three gives an emphasis inside a strong emphasis, because the two
///   characters used for the strong emphasis are taken off the run first.

///|
/// A piece of the inline stream, before the emphasis has been resolved.
///
priv enum Piece {
  Lit(String)
  Node(Inline)
  Run(Delim)
}

///|
/// A delimiter run: a run of `*` or `_`, with what the flanking rules say
/// about it.
///
priv struct Delim {
  ch : Char
  /// the length of the run as it was written
  orig_len : Int32
  can_open : Bool
  can_close : Bool
}

///|
/// One cell of the inline stream.
///
/// The cells live in an array and are linked to one another, because
/// resolving an emphasis moves the cells between the opener and the closer
/// into a new cell, and a plain array would make that a copy of the rest of
/// the stream.
///
priv struct Cell {
  piece : Piece
  prev : Int32
  next : Int32
  /// how many characters of the delimiter run are still literal text
  numdelims : Int32
}

///|
/// One entry of the delimiter stack.
///
priv struct SNode {
  cell : Int32
  delim : Delim
  prev : Int32
  next : Int32
}

///|
/// The string of `n` copies of `c`.
///
fn repeat_char(c : Char, n : Int32) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    sb.write_char(c)
    i += 1
  }
  sb.to_string()
}

///|
/// The inline nodes a cell stands for.
///
fn cell_inline(cells : Array[Cell], idx : Int32) -> Inline {
  let c = cells[idx]
  match c.piece {
    Lit(s) => Text(s)
    Node(n) => n
    Run(d) => Text(repeat_char(d.ch, c.numdelims))
  }
}

///|
/// Put a cell between two cells that are already linked.
///
fn cell_insert_between(
  cells : Array[Cell],
  before : Int32,
  after : Int32,
  piece : Piece,
) -> Unit {
  let idx = cells.length()
  cells.push({ piece, prev: before, next: after, numdelims: 0, })
  let b = cells[before]
  cells[before] = {
    piece: b.piece,
    prev: b.prev,
    next: idx,
    numdelims: b.numdelims,
  }
  let a = cells[after]
  cells[after] = {
    piece: a.piece,
    prev: idx,
    next: a.next,
    numdelims: a.numdelims,
  }
}

///|
/// Take a cell out of the stream.
///
fn cell_unlink(cells : Array[Cell], idx : Int32) -> Unit {
  let c = cells[idx]
  if c.prev >= 0 {
    let p = cells[c.prev]
    cells[c.prev] = {
      piece: p.piece,
      prev: p.prev,
      next: c.next,
      numdelims: p.numdelims,
    }
  }
  if c.next >= 0 {
    let n = cells[c.next]
    cells[c.next] = {
      piece: n.piece,
      prev: c.prev,
      next: n.next,
      numdelims: n.numdelims,
    }
  }
}

///|
/// The bucket the lower bound of the opener search is kept in: the character
/// and, for `*`, the length of the closing run modulo three, and whether
/// the closing run could also open.
///
/// The `_` runs share one bucket, because an underscore can only open at the
/// start of a word, so the length of the closing run does not say anything
/// about it.
///
fn bucket_of(d : Delim) -> Int32 {
  if d.ch == '_' {
    2
  } else {
    3 + (if d.can_open { 3 } else { 0 }) + d.orig_len % 3
  }
}

///|
/// The "rule of three": two runs whose lengths add up to a multiple of three
/// may not match when one of them could also be used the other way round -
/// unless both lengths are multiples of three themselves.
///
fn odd_match(closer : Delim, opener : Delim) -> Bool {
  (closer.can_open || opener.can_close) &&
  closer.orig_len % 3 != 0 &&
  (opener.orig_len + closer.orig_len) % 3 == 0
}

///|
/// Resolve the emphasis in the stream, and return the inline nodes.
///
/// The pieces are laid out as a linked list first, because resolving an
/// emphasis moves the pieces between the opener and the closer into a new
/// piece, and an array alone would make that a copy of the rest of the
/// stream.
///
fn resolve_emphasis(pieces : Array[Piece]) -> Array[Inline] {
  // ---- lay the pieces out as a list
  let cells : Array[Cell] = []
  let mut prev = -1
  let mut i = 0
  while i < pieces.length() {
    let p = pieces[i]
    let numdelims = match p {
      Run(d) => d.orig_len
      _ => 0
    }
    cells.push({ piece: p, prev, next: -1, numdelims, })
    if prev >= 0 {
      let q = cells[prev]
      cells[prev] = {
        piece: q.piece,
        prev: q.prev,
        next: i,
        numdelims: q.numdelims,
      }
    }
    prev = i
    i += 1
  }
  let head = if cells.is_empty() { -1 } else { 0 }
  // ---- the delimiter stack
  let nodes : Array[SNode] = []
  let mut top = -1
  let mut i = head
  while i >= 0 {
    match cells[i].piece {
      Run(d) => {
        let n = nodes.length()
        nodes.push({ cell: i, delim: d, prev: top, next: -1, })
        if top >= 0 {
          let t = nodes[top]
          nodes[top] = { cell: t.cell, delim: t.delim, prev: t.prev, next: n, }
        }
        top = n
      }
      _ => ()
    }
    i = cells[i].next
  }
  // ---- the lower bound of the opener search, per bucket
  let bottoms : Array[Int32] = [-1, -1, -1, -1, -1, -1, -1, -1, -1]
  // ---- resolve
  // The walk over the closers starts at the bottom of the stack and moves
  // towards the top: the first run that may close is the one that was found
  // first in the text, and it is the one that pairs up first.
  let mut closer = if nodes.is_empty() { -1 } else { 0 }
  while closer >= 0 {
    let cd = nodes[closer].delim
    if !cd.can_close {
      closer = nodes[closer].next
      continue
    }
    let bucket = bucket_of(cd)
    let bottom = bottoms[bucket]
    // ---- look back for the nearest run that may open
    let mut opener = nodes[closer].prev
    let mut opener_found = false
    while opener >= 0 && opener != bottom {
      let od = nodes[opener].delim
      let odd = odd_match(cd, od)
      if od.ch == cd.ch && od.can_open && !odd {
        opener_found = true
        break
      }
      opener = nodes[opener].prev
    }
    let old_closer = closer
    if !opener_found {
      // no opener: remember how far back the search has been, and drop the
      // closer when it could not have opened either
      closer = nodes[old_closer].next
      bottoms[bucket] = nodes[old_closer].prev
      if !cd.can_open {
        snode_unlink(nodes, old_closer)
      }
      continue
    }
    // ---- the pair becomes an emphasis
    let ocell = nodes[opener].cell
    let ccell = nodes[closer].cell
    let use_n = if cells[ccell].numdelims >= 2 && cells[ocell].numdelims >= 2 {
      2
    } else {
      1
    }
    let inner = cell_take_between(cells, ocell, ccell)
    let node = if use_n == 2 { Strong(inner) } else { Emphasis(inner) }
    cell_insert_between(cells, ocell, ccell, Node(node))
    // the runs between the two are spent
    snode_remove_between(nodes, opener, closer)
    // the two runs give up the characters they used
    let o = cells[ocell]
    cells[ocell] = {
      piece: o.piece,
      prev: o.prev,
      next: o.next,
      numdelims: o.numdelims - use_n,
    }
    let c = cells[ccell]
    cells[ccell] = {
      piece: c.piece,
      prev: c.prev,
      next: c.next,
      numdelims: c.numdelims - use_n,
    }
    if cells[ocell].numdelims == 0 {
      cell_unlink(cells, ocell)
      snode_unlink(nodes, opener)
    }
    if cells[ccell].numdelims == 0 {
      cell_unlink(cells, ccell)
      let next = nodes[closer].next
      snode_unlink(nodes, closer)
      closer = next
    }
  }
  // ---- what is left of the stream
  let out : Array[Inline] = []
  let mut i = head
  while i >= 0 {
    let c = cells[i]
    match c.piece {
      Lit(s) => out.push(Text(s))
      Node(n) => out.push(n)
      Run(d) =>
        if c.numdelims > 0 {
          out.push(Text(repeat_char(d.ch, c.numdelims)))
        }
    }
    i = c.next
  }
  out
}

///|
/// Take the cells between two cells out of the stream and return the inline
/// nodes they stand for.
///
fn cell_take_between(
  cells : Array[Cell],
  before : Int32,
  after : Int32,
) -> Array[Inline] {
  let out : Array[Inline] = []
  let mut i = cells[before].next
  while i >= 0 && i != after {
    out.push(cell_inline(cells, i))
    i = cells[i].next
  }
  // link the two ends together
  let b = cells[before]
  cells[before] = {
    piece: b.piece,
    prev: b.prev,
    next: after,
    numdelims: b.numdelims,
  }
  let a = cells[after]
  cells[after] = {
    piece: a.piece,
    prev: before,
    next: a.next,
    numdelims: a.numdelims,
  }
  out
}

///|
/// Take a stack entry out of the stack.
///
fn snode_unlink(nodes : Array[SNode], idx : Int32) -> Unit {
  let n = nodes[idx]
  if n.prev >= 0 {
    let p = nodes[n.prev]
    nodes[n.prev] = {
      cell: p.cell,
      delim: p.delim,
      prev: p.prev,
      next: n.next,
    }
  }
  if n.next >= 0 {
    let x = nodes[n.next]
    nodes[n.next] = {
      cell: x.cell,
      delim: x.delim,
      prev: n.prev,
      next: x.next,
    }
  }
}

///|
/// Take the stack entries between two of them out of the stack. The runs they
/// stand for stay in the stream as literal text.
///
fn snode_remove_between(
  nodes : Array[SNode],
  opener : Int32,
  closer : Int32,
) -> Unit {
  let mut i = nodes[closer].prev
  while i >= 0 && i != opener {
    let prev = nodes[i].prev
    snode_unlink(nodes, i)
    i = prev
  }
}
