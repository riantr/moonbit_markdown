///|
/// Tests for the Markdown parser and HTML renderer.

///|
test "heading levels" {
  let blocks = @md.parse_document("# One\n## Two\n###### Six\n####### Seven\n")
  // seven hashes is not a heading: it stays a paragraph
  @test.assert_eq(blocks.length(), 4)
  match blocks[0] {
    Heading(l, cs) => {
      @test.assert_eq(l, 1)
      @test.assert_eq(@md.plain_text(cs), "One")
    }
    _ => @test.fail("expected heading")
  }
  match blocks[2] {
    Heading(l, _) => @test.assert_eq(l, 6)
    _ => @test.fail("expected heading")
  }
  match blocks[3] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "####### Seven")
    _ => @test.fail("expected paragraph")
  }
}

///|
test "paragraph and soft break" {
  let blocks = @md.parse_document("one\ntwo\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Paragraph(cs) => {
      @test.assert_eq(cs.length(), 3)
      match cs[1] {
        SoftBreak => ()
        _ => @test.fail("expected soft break")
      }
    }
    _ => @test.fail("expected paragraph")
  }
}

///|
test "emphasis and strong" {
  let blocks = @md.parse_document("*a* **b** _c_ __d__\n")
  match blocks[0] {
    Paragraph(cs) => {
      // emphasis, space, strong, space, emphasis, space, strong
      @test.assert_eq(cs.length(), 7)
      match cs[0] {
        Emphasis(inner) => @test.assert_eq(@md.plain_text(inner), "a")
        _ => @test.fail("expected emphasis")
      }
      match cs[2] {
        Strong(inner) => @test.assert_eq(@md.plain_text(inner), "b")
        _ => @test.fail("expected strong")
      }
      match cs[4] {
        Emphasis(inner) => @test.assert_eq(@md.plain_text(inner), "c")
        _ => @test.fail("expected emphasis")
      }
      match cs[6] {
        Strong(inner) => @test.assert_eq(@md.plain_text(inner), "d")
        _ => @test.fail("expected strong")
      }
    }
    _ => @test.fail("expected paragraph")
  }
}

///|
test "underscore inside a word stays literal" {
  let blocks = @md.parse_document("snake_case_name\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "snake_case_name")
    _ => @test.fail("expected paragraph")
  }
}

///|
test "code span beats emphasis" {
  let blocks = @md.parse_document("`*not emphasis*`\n")
  match blocks[0] {
    Paragraph(cs) => {
      @test.assert_eq(cs.length(), 1)
      match cs[0] {
        Code(t) => @test.assert_eq(t, "*not emphasis*")
        _ => @test.fail("expected code")
      }
    }
    _ => @test.fail("expected paragraph")
  }
}

///|
test "link and image" {
  let blocks = @md.parse_document(
    "[text](http://example.com/a) ![alt](img.png)\n",
  )
  match blocks[0] {
    Paragraph(cs) => {
      // link, space, image
      @test.assert_eq(cs.length(), 3)
      match cs[0] {
        Link(href, title, inner) => {
          @test.assert_eq(href, "http://example.com/a")
          @test.assert_eq(title, "")
          @test.assert_eq(@md.plain_text(inner), "text")
        }
        _ => @test.fail("expected link")
      }
      match cs[2] {
        Image(src, alt) => {
          @test.assert_eq(src, "img.png")
          @test.assert_eq(alt, "alt")
        }
        _ => @test.fail("expected image")
      }
    }
    _ => @test.fail("expected paragraph")
  }
}

///|
test "fenced code block with info string" {
  let blocks = @md.parse_document(
    "```moonbit\nfn main {\n  println(\"hi\")\n}\n```\n",
  )
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    CodeBlock(info, code) => {
      @test.assert_eq(info, "moonbit")
      @test.assert_eq(code, "fn main {\n  println(\"hi\")\n}\n")
    }
    _ => @test.fail("expected code block")
  }
}

///|
test "mermaid fence becomes a mermaid block" {
  let blocks = @md.parse_document(
    "```mermaid\nstateDiagram-v2\n  [*] --> a\n```\n",
  )
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Mermaid(src) => @test.assert_eq(src, "stateDiagram-v2\n  [*] --> a\n")
    _ => @test.fail("expected mermaid block")
  }
}

///|
test "blockquote" {
  let blocks = @md.parse_document("> quoted **text**\n> more\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Quote(inner) => {
      @test.assert_eq(inner.length(), 1)
      match inner[0] {
        Paragraph(cs) => {
          // the quote marker is stripped, the inline markup is not
          @test.assert_eq(@md.plain_text(cs), "quoted text more")
          match cs[1] {
            Strong(inner2) => @test.assert_eq(@md.plain_text(inner2), "text")
            _ => @test.fail("expected strong")
          }
        }
        _ => @test.fail("expected paragraph")
      }
    }
    _ => @test.fail("expected quote")
  }
}

///|
test "unordered list with nested content" {
  let blocks = @md.parse_document("- one\n- two\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    List(ordered, _, items) => {
      @test.assert_eq(ordered, false)
      @test.assert_eq(items.length(), 2)
      @test.assert_eq(items[0].task, 0)
    }
    _ => @test.fail("expected list")
  }
}

///|
test "ordered list" {
  let blocks = @md.parse_document("1. one\n2. two\n")
  match blocks[0] {
    List(ordered, _, items) => {
      @test.assert_eq(ordered, true)
      @test.assert_eq(items.length(), 2)
    }
    _ => @test.fail("expected list")
  }
}

///|
test "task list item" {
  let blocks = @md.parse_document("- [x] done\n- [ ] todo\n")
  match blocks[0] {
    List(_, _, items) => {
      @test.assert_eq(items.length(), 2)
      @test.assert_eq(items[0].task, 2)
      @test.assert_eq(items[1].task, 1)
    }
    _ => @test.fail("expected list")
  }
}

///|
test "thematic break is not a list" {
  let blocks = @md.parse_document("---\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Rule => ()
    _ => @test.fail("expected rule")
  }
}

///|
test "table with alignments" {
  let src = "| a | b | c |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |\n"
  let blocks = @md.parse_document(src)
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Table(head, align, rows) => {
      @test.assert_eq(head.length(), 3)
      @test.assert_eq(align.length(), 3)
      @test.assert_eq(align[0], "left")
      @test.assert_eq(align[1], "center")
      @test.assert_eq(align[2], "right")
      @test.assert_eq(rows.length(), 1)
      @test.assert_eq(rows[0].cells.length(), 3)
    }
    _ => @test.fail("expected table")
  }
}

///|
test "html block passes through" {
  let blocks = @md.parse_document("<div class=\"x\">\nhello\n</div>\n")
  match blocks[0] {
    HtmlBlock(h) => @test.assert_eq(h.has_prefix("<div class=\"x\">"), true)
    _ => @test.fail("expected html block")
  }
}

///|
test "escapes are honoured" {
  let blocks = @md.parse_document("\\*not emphasis\\*\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "*not emphasis*")
    _ => @test.fail("expected paragraph")
  }
}

///|
test "hard break needs two spaces" {
  let blocks = @md.parse_document("a  \nb\n")
  match blocks[0] {
    Paragraph(cs) => {
      @test.assert_eq(cs.length(), 3)
      match cs[1] {
        HardBreak => ()
        _ => @test.fail("expected hard break")
      }
    }
    _ => @test.fail("expected paragraph")
  }
}

///|
test "render escapes html" {
  let html = @md.render("a < b & c\n")
  @test.assert_eq(html.contains("a &lt; b &amp; c"), true)
}

///|
test "render produces a heading with an id" {
  let html = @md.render("## Hello World\n")
  @test.assert_eq(
    html.contains("<h2 id=\"hello-world\">Hello World</h2>"),
    true,
  )
}

///|
test "render emits a mermaid div" {
  let html = @md.render("```mermaid\ngraph TD;\nA-->B;\n```\n")
  @test.assert_eq(html.contains("<div class=\"mermaid\">"), true)
  @test.assert_eq(html.contains("graph TD;"), true)
}

///|
test "render emits a table" {
  let html = @md.render("| a | b |\n| - | - |\n| 1 | 2 |\n")
  @test.assert_eq(html.contains("<table>"), true)
  @test.assert_eq(html.contains("<th>a</th>"), true)
  @test.assert_eq(html.contains("<td>1</td>"), true)
}

///|
test "render a full page is self contained" {
  let page = @md.render_page("T", "<p>x</p>", "")
  @test.assert_eq(page.has_prefix("<!DOCTYPE html>"), true)
  @test.assert_eq(page.contains("<title>T</title>"), true)
  @test.assert_eq(page.contains("<main>"), true)
}

///|
test "table of contents" {
  let blocks = @md.parse_document("# A\n## B\n## C\n")
  let toc = @md.collect_toc(blocks)
  @test.assert_eq(toc.length(), 3)
  @test.assert_eq(toc[0].text, "A")
  @test.assert_eq(toc[1].level, 2)
  @test.assert_eq(toc[1].id, "b")
}

///|
test "non ascii text survives" {
  let blocks = @md.parse_document("héllo — wörld\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "héllo — wörld")
    _ => @test.fail("expected paragraph")
  }
}

///|
test "the runtime is only needed when the document holds a diagram" {
  // a document without a diagram must not pull in the 2.6 MB runtime
  @test.assert_eq(@md.needs_runtime(@md.parse_document("# Title\n\ntext\n")), false)
  @test.assert_eq(@md.needs_runtime(@md.parse_document("```mermaid\ngraph TD;\nA-->B;\n```\n")), true)
  // a fenced block that is not mermaid is just code
  @test.assert_eq(@md.needs_runtime(@md.parse_document("```\nnot a diagram\n```\n")), false)
  // a document that only mentions the markup is not a document with a diagram
  @test.assert_eq(
    @md.needs_runtime(@md.parse_document("```\n<div class=\"mermaid\">\n```\n")),
    false,
  )
  // the rule has to agree with what the renderer actually emits, or the
  // runtime is either dropped from a page that needs it or added to one that
  // does not
  let with_mermaid = @md.parse_document("```mermaid\ngraph TD;\nA-->B;\n```\n")
  @test.assert_eq(
    @md.needs_runtime(with_mermaid),
    @md.render_blocks(with_mermaid).contains("<div class=\"mermaid\">"),
  )
}

///|
test "a tab is four columns of indentation" {
  // a tab at the head of a line is an indented code block, not a paragraph
  let blocks = @md.parse_document("\tfoo\tbaz\t\tbim\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    CodeBlock(_, content) => @test.assert_eq(content, "foo\tbaz\t\tbim\n")
    _ => @test.fail("expected a code block")
  }
}

///|
test "four columns of indentation make a code block, not a break" {
  let blocks = @md.parse_document("    ***\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    CodeBlock(_, content) => @test.assert_eq(content, "***\n")
    _ => @test.fail("expected a code block")
  }
}

///|
test "character references are decoded" {
  let blocks = @md.parse_document("&amp; &copy; &#233; &#x41; &MadeUp;\n")
  match blocks[0] {
    Paragraph(cs) => {
      @test.assert_eq(@md.plain_text(cs), "& © é A &MadeUp;")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a link destination follows the CommonMark rules" {
  // an empty destination between angle brackets is a link
  let blocks = @md.parse_document("[link](<>)\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
  // a bare destination may not hold a space, so this is not a link at all
  let blocks = @md.parse_document("[link](/my uri)\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "[link](/my uri)")
    _ => @test.fail("expected a paragraph")
  }
  // between angle brackets a space is written back as %20
  let blocks = @md.parse_document("[link](</my uri>)\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "/my%20uri")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a link may carry a title" {
  let blocks = @md.parse_document("[link](/url \"the title\")\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, title, _) => {
        @test.assert_eq(href, "/url")
        @test.assert_eq(title, "the title")
      }
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "link reference definitions" {
  let blocks = @md.parse_document("[foo][bar]\n\n[bar]: /url \"title\"\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, title, _) => {
        @test.assert_eq(href, "/url")
        @test.assert_eq(title, "title")
      }
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
  // the shortcut form: the text is the label
  let blocks = @md.parse_document("[bar]\n\n[bar]: /url\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "/url")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
  // an undefined label stays literal text
  let blocks = @md.parse_document("[nope]\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "[nope]")
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a different marker starts a different list" {
  let blocks = @md.parse_document("- foo\n+ bar\n")
  @test.assert_eq(blocks.length(), 2)
  @test.assert_eq(@md.render_blocks(blocks).contains("<ul><li>foo</li></ul>"), true)
}

///|
test "an ordered list only interrupts a paragraph when it starts with 1" {
  // this is a paragraph, not a list
  let blocks = @md.parse_document("The number of doors is\n14.  The number of windows is 6.\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Paragraph(_) => ()
    _ => @test.fail("expected a paragraph")
  }
  // this one does start a list
  let blocks = @md.parse_document("The number of doors is\n1.  The number of windows is 6.\n")
  @test.assert_eq(blocks.length(), 2)
}

///|
test "an autolink may carry any scheme" {
  let blocks = @md.parse_document("<localhost:5001/foo>\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "localhost:5001/foo")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "an inline HTML comment is raw" {
  let html = @md.render("foo <!-- a comment -->\n")
  @test.assert_eq(html.contains("<!-- a comment -->"), true)
}

///|
test "an html block of a comment runs to its own marker" {
  let blocks = @md.parse_document("<!-- foo\n\nbar -->\nokay\n")
  @test.assert_eq(blocks.length(), 2)
  match blocks[0] {
    HtmlBlock(h) => @test.assert_eq(h.contains("bar -->"), true)
    _ => @test.fail("expected an html block")
  }
  match blocks[1] {
    Paragraph(_) => ()
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a block level tag ends at the blank line" {
  let blocks = @md.parse_document("<div>\n*foo*\n\nbar\n")
  @test.assert_eq(blocks.length(), 2)
  match blocks[0] {
    HtmlBlock(h) => @test.assert_eq(h.contains("*foo*"), true)
    _ => @test.fail("expected an html block")
  }
}

///|
test "the info string of a fence may not hold a backtick" {
  // "``` aa ```" is a line of text, not a code block
  let blocks = @md.parse_document("``` aa ```\nfoo\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Paragraph(_) => ()
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "an email autolink gets a mailto" {
  let blocks = @md.parse_document("<foo@bar.example.com>\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "mailto:foo@bar.example.com")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a link destination is percent encoded" {
  let blocks = @md.parse_document("[foo](/f&ouml;&ouml;)\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "/f%C3%B6%C3%B6")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "an illegal attribute name makes the tag literal text" {
  let blocks = @md.parse_document("<a h*#ref=\"hi\">\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "<a h*#ref=\"hi\">")
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a heading may be indented by three columns" {
  let blocks = @md.parse_document(" ### foo\n")
  match blocks[0] {
    Heading(l, cs) => {
      @test.assert_eq(l, 3)
      @test.assert_eq(@md.plain_text(cs), "foo")
    }
    _ => @test.fail("expected a heading")
  }
}

///|
test "a closing sequence of hashes needs a space in front of it" {
  let blocks = @md.parse_document("# foo#\n")
  match blocks[0] {
    Heading(_, cs) => @test.assert_eq(@md.plain_text(cs), "foo#")
    _ => @test.fail("expected a heading")
  }
}

///|
test "a collapsed reference link names the label by its text" {
  let blocks = @md.parse_document("![foo][]\n\n[foo]: /url \"title\"\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Image(src, alt) => {
        @test.assert_eq(src, "/url")
        @test.assert_eq(alt, "foo")
      }
      _ => @test.fail("expected an image")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "an escaped ampersand keeps the entity literal" {
  let blocks = @md.parse_document("\\&ouml;\n")
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "&ouml;")
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a list keeps its items together over a blank line" {
  let blocks = @md.parse_document("- a\n\n- b\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    List(_, loose, items) => {
      @test.assert_eq(loose, true)
      @test.assert_eq(items.length(), 2)
    }
    _ => @test.fail("expected a list")
  }
}

///|
test "the content of a list item starts after the spaces of the marker" {
  // "-    foo" puts the content five columns in, so "  bar" is not part of it
  let blocks = @md.parse_document("-    foo\n\n  bar\n")
  @test.assert_eq(blocks.length(), 2)
}

///|
test "an empty destination is a link" {
  let blocks = @md.parse_document("[link]()\n")
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a link may not hold another link" {
  // the inner link is the one that counts, the text around it stays text
  let blocks = @md.parse_document("[foo [bar](/uri)](/uri)\n")
  match blocks[0] {
    Paragraph(cs) => {
      @test.assert_eq(@md.plain_text(cs), "[foo bar](/uri)")
      match cs[1] {
        Link(href, _, _) => @test.assert_eq(href, "/uri")
        _ => @test.fail("expected a link")
      }
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a definition may be broken over lines" {
  let blocks = @md.parse_document("[foo]:\n/url\n\n[foo]\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Paragraph(cs) => match cs[0] {
      Link(href, _, _) => @test.assert_eq(href, "/url")
      _ => @test.fail("expected a link")
    }
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a definition inside a code block is no definition" {
  let blocks = @md.parse_document("```\n[foo]: /url\n```\n\n[foo]\n")
  @test.assert_eq(blocks.length(), 2)
  match blocks[1] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "[foo]")
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "a definition may not interrupt a paragraph" {
  let blocks = @md.parse_document("Foo\n[bar]: /baz\n")
  @test.assert_eq(blocks.length(), 1)
  match blocks[0] {
    Paragraph(cs) => @test.assert_eq(@md.plain_text(cs), "Foo [bar]: /baz")
    _ => @test.fail("expected a paragraph")
  }
}

///|
test "the one-page switch changes the wrapper and nothing else" {
  let plain = @md.render_page("T", "<p>x</p>", "")
  let one = @md.render_page("T", "<p>x</p>", "", figures_one_page=true)
  // the class is the hook the figure rules hang on, so the default page has
  // to have no trace of it
  @test.assert_eq(plain.contains("figures-one-page"), false)
  @test.assert_eq(one.contains("<main class=\"figures-one-page\">\n"), true)
  @test.assert_eq(one.contains(@md.FIGURE_CSS), true)
  // and the rules are a print media block: on screen the page still reads as
  // a document, so the switch cannot change what a reader sees
  @test.assert_eq(@md.FIGURE_CSS.contains("@media print{"), true)
  @test.assert_eq(@md.DEFAULT_CSS.contains("break-before"), false)
  // the body is rendered identically - only the wrapper differs
  @test.assert_eq(plain.contains("<main>\n<p>x</p></main>"), true)
  @test.assert_eq(one.contains("<p>x</p></main>"), true)
}