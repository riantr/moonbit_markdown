///|
/// The kinds of raw HTML block, as CommonMark defines them.
///
/// The kind decides where the block ends. A comment, a processing
/// instruction, a declaration, a CDATA section and the tags that hold
/// literal content end at their own closing marker; a block level tag and a
/// tag that stands alone on the line end at the next blank line.

///|
priv enum HtmlKind {
  /// <pre>, <script>, <style>, <textarea>
  Pre
  /// <!-- ... -->
  Comment
  /// <? ... ?>
  Instruction
  /// <!DOCTYPE ...>
  Declaration
  /// <![CDATA[ ... ]]>
  Cdata
  /// a block level tag, such as <div> or </div>
  BlockTag
  /// a complete tag that stands alone on the line
  Standalone
}

///|
/// The kind of raw HTML block the line starts, or None when the line does
/// not start one.
///
/// A line may be indented by up to three spaces. All the kinds but the last
/// one may interrupt a paragraph; the last one may not, so that a tag
/// inside a wrapped paragraph stays part of the text.

///|
fn html_block_kind(s : String) -> HtmlKind? {
  let cs = chars(s)
  let mut i = 0
  while i < cs.length() && cs[i] == ' ' && i < 3 {
    i += 1
  }
  if i >= cs.length() || cs[i] != '<' {
    return None
  }
  // the tags that hold literal content
  let (name, after) = tag_name_at(cs, i + 1)
  if name == "pre" || name == "script" || name == "style" || name == "textarea" {
    if after >= cs.length() {
      return Some(HtmlKind::Pre)
    }
    let c = cs[after]
    if c == ' ' || c == '\t' || c == '>' {
      return Some(HtmlKind::Pre)
    }
  }
  // a comment, a processing instruction, a CDATA section, a declaration
  if has_at(cs, i, "<!--") {
    return Some(HtmlKind::Comment)
  }
  if has_at(cs, i, "<?") {
    return Some(HtmlKind::Instruction)
  }
  if has_at(cs, i, "<![CDATA[") {
    return Some(HtmlKind::Cdata)
  }
  if i + 2 < cs.length() && cs[i + 1] == '!' && cs[i + 2].is_ascii_alphabetic() {
    return Some(HtmlKind::Declaration)
  }
  // a block level tag, opening or closing
  let mut j = i + 1
  if j < cs.length() && cs[j] == '/' {
    j += 1
  }
  let (name, after) = tag_name_at(cs, j)
  if is_block_tag(name) {
    if after >= cs.length() {
      return Some(HtmlKind::BlockTag)
    }
    let c = cs[after]
    if c == ' ' || c == '\t' || c == '>' {
      return Some(HtmlKind::BlockTag)
    }
    if c == '/' && after + 1 < cs.length() && cs[after + 1] == '>' {
      return Some(HtmlKind::BlockTag)
    }
  }
  // a complete tag that stands alone on the line
  match scan_html_tag(cs, i) {
    Some((tag, end)) => {
      let tag = tag.to_lower()
      if tag == "pre" || tag == "script" || tag == "style" || tag == "textarea" {
        return None
      }
      // nothing but spaces and tabs may follow the tag
      let mut k = end
      while k < cs.length() && (cs[k] == ' ' || cs[k] == '\t') {
        k += 1
      }
      if k >= cs.length() {
        return Some(HtmlKind::Standalone)
      }
      None
    }
    None => None
  }
}

///|
/// The lower case name of the tag at `at` and the index after it.
///
/// The name holds the letters only; what follows the name is looked at by
/// the caller.
///
fn tag_name_at(cs : Chars, at : Int32) -> (String, Int32) {
  let mut j = at
  while j < cs.length() && cs[j].is_ascii_alphabetic() {
    j += 1
  }
  (text(cs, at, j).to_lower(), j)
}

///|
/// Is this one of the block level tags? A line that opens one of them
/// starts an HTML block, whatever else is on the line.
///
fn is_block_tag(name : String) -> Bool {
  for t in block_tags() {
    if t == name {
      return true
    }
  }
  false
}

///|
/// Does the block of this kind end at its own marker?
///
/// The tags that hold literal content, the comments, the processing
/// instructions, the declarations and the CDATA sections end at their
/// closing marker, and they may hold blank lines. The other kinds end at the
/// next blank line.
///
fn html_block_ends_at_marker(kind : HtmlKind) -> Bool {
  match kind {
    Pre => true
    Comment => true
    Instruction => true
    Declaration => true
    Cdata => true
    BlockTag => false
    Standalone => false
  }
}

///|
/// Does the line hold the marker that ends the block of this kind?
///
fn html_block_ends(kind : HtmlKind, line : String) -> Bool {
  match kind {
    Pre =>
      contains_text(line, "</pre>") ||
      contains_text(line, "</script>") ||
      contains_text(line, "</style>") ||
      contains_text(line, "</textarea>")
    Comment => contains_text(line, "-->")
    Instruction => contains_text(line, "?>")
    Declaration => contains_text(line, ">")
    Cdata => contains_text(line, "]]>")
    BlockTag => false
    Standalone => false
  }
}

///|
/// May a block of this kind interrupt a paragraph?
///
/// Only the tag that stands alone on its line may not: a long tag inside a
/// wrapped paragraph should stay part of the text.
///
fn html_block_interrupts(kind : HtmlKind) -> Bool {
  match kind {
    Standalone => false
    _ => true
  }
}
