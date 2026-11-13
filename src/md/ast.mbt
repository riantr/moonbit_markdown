///|
/// The document model shared by the parser and the HTML renderer.

///|
/// Two block kinds exist that no other Markdown implementation needs:
/// `Mermaid` carries a Mermaid diagram source, and a `CodeBlock` whose info
/// string is "mermaid" is rendered into one. That is the seam where this
/// module's Markdown side and its Mermaid side meet.

///|
pub enum Inline {
  Text(String)
  Code(String)
  Emphasis(Array[Inline])
  Strong(Array[Inline])
  /// the destination, the title, the content
  Link(String, String, Array[Inline])
  Image(String, String)
  RawHtml(String)
  HardBreak
  SoftBreak
}

///|
pub enum Block {
  Heading(Int32, Array[Inline])
  Paragraph(Array[Inline])
  /// info string, source text
  CodeBlock(String, String)
  /// a Mermaid diagram: the diagram source, verbatim
  Mermaid(String)
  HtmlBlock(String)
  Quote(Array[Block])
  /// ordered?, loose?, items
  ///
  /// A list is loose when its items are separated by blank lines, or when
  /// one of its items holds two blocks with a blank line between them. The
  /// paragraphs of a loose list are written as paragraphs, the ones of a
  /// tight list are not.
  List(Bool, Bool, Array[ListItem])
  Rule
  /// head cells, alignments, body rows
  Table(Array[TableCell], Array[String], Array[TableRow])
}

///|
pub struct ListItem {
  blocks : Array[Block]
  /// 0 = not a task item, 1 = unchecked, 2 = checked
  task : Int32
}

///|
pub struct TableCell {
  content : Array[Inline]
}

///|
pub struct TableRow {
  cells : Array[TableCell]
}
