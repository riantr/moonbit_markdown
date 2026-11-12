///|
/// Tests for the Mermaid scan parser and the HTML page builder.

///|
/// The fixture is a miniature of what the generator emits: a `%%` header, a
/// `scan` edge per file, a composite state with states and notes.

///|
fn fixture() -> String {
  let lines = [
    "%% target=riantr/moonbit_doubleML version=0.164.28 moonbit=0.1.20261012 files=2 parsed=2 partial=0 actionable=1 notices=3 unreliable=0 withheld=0 total=1",
    "stateDiagram-v2", "    direction TB", "    scan --> f1 : 0 actionable, 1 notice(s), parsed",
    "    state \"f1 — .repos/a/one.mbt\" as f1 {", "        direction TB", "        [*] --> f1_lex",
    "        state \"lexed\" as f1_lex", "        f1_lex --> f1_struct : whole file read",
    "        state \"inspection 1/3 — structural\" as f1_struct", "        f1_struct --> f1_n0 : notice ParseError",
    "        state \"NOTICE — ParseError @77:15 — if expression is outside the analyzed subset\" as f1_n0",
    "        note right of f1_n0", "            NOTICE — counted in `notices`, excluded from `actionable`.",
    "            ParseError covers a form this analyzer does not model.", "        end note",
    "    }", "    scan --> f98 : 1 actionable, 2 notice(s), parsed", "    state \"f98 — .repos/b/two.mbt\" as f98 {",
    "        direction TB", "        [*] --> f98_lex", "        state \"lexed\" as f98_lex",
    "        f98_lex --> f98_struct : whole file read", "        state \"inspection 1/3 — structural\" as f98_struct",
    "        f98_struct --> f98_e8 : defect OperatorMismatch", "        state \"OperatorMismatch @6795:17 — unsupported operand types for '==': '[int]' and '[int]'\" as f98_e8",
    "        note right of f98_e8", "            WHY: One of four shapes: `!` applied to a non-boolean.",
    "        end note", "        f98_struct --> f98_n0 : notice ParseError", "        state \"NOTICE — ParseError @77:15 — if expression is outside the analyzed subset\" as f98_n0",
    "        note right of f98_n0", "            NOTICE — counted in `notices`, excluded from `actionable`.",
    "            ParseError covers a form this analyzer does not model.", "        end note",
    "        f98_struct --> f98_n1 : notice ParseError", "        state \"NOTICE — ParseError @97:22 — if expression is outside the analyzed subset\" as f98_n1",
    "        note right of f98_n1", "            NOTICE — counted in `notices`, excluded from `actionable`.",
    "            ParseError covers a form this analyzer does not model.", "        end note",
    "    }",
  ]
  lines.join("\n")
}

///|
test "the header is parsed" {
  let d = @mermaid.parse_diagram(fixture())
  @test.assert_eq(d.meta.length(), 11)
  @test.assert_eq(@mermaid.meta_of(d, "target"), "riantr/moonbit_doubleML")
  @test.assert_eq(@mermaid.meta_of(d, "files"), "2")
  @test.assert_eq(@mermaid.meta_of(d, "notices"), "3")
}

///|
test "the files are parsed" {
  let d = @mermaid.parse_diagram(fixture())
  @test.assert_eq(d.files.length(), 2)
  @test.assert_eq(d.files[0].id, "f1")
  @test.assert_eq(d.files[0].path, ".repos/a/one.mbt")
  @test.assert_eq(d.files[0].actionable, 0)
  @test.assert_eq(d.files[0].notice_count, 1)
  @test.assert_eq(d.files[1].id, "f98")
  @test.assert_eq(d.files[1].path, ".repos/b/two.mbt")
  @test.assert_eq(d.files[1].actionable, 1)
  @test.assert_eq(d.files[1].notice_count, 2)
}

///|
test "states and notes are parsed" {
  let d = @mermaid.parse_diagram(fixture())
  let f1 = d.files[0]
  // lexed, inspection 1/3, the NOTICE
  @test.assert_eq(f1.states.length(), 3)
  @test.assert_eq(f1.states[0].id, "f1_lex")
  @test.assert_eq(f1.states[0].msg, "lexed")
  @test.assert_eq(f1.states[2].id, "f1_n0")
  @test.assert_eq(f1.notes.length(), 1)
  @test.assert_eq(f1.notes[0].owner, "f1_n0")
  @test.assert_eq(
    f1.notes[0].text,
    "NOTICE — counted in `notices`, excluded from `actionable`. ParseError covers a form this analyzer does not model.",
  )
}

///|
test "notices and findings are told apart" {
  let d = @mermaid.parse_diagram(fixture())
  // three NOTICE states, one actionable finding, the rest are chain states
  @test.assert_eq(@mermaid.drawn_notices(d), 3)
  @test.assert_eq(@mermaid.drawn_findings(d), 1)
  @test.assert_eq(@mermaid.drawn_notes(d), 4)
}

///|
test "the overview graph is flat and lists every file" {
  let d = @mermaid.parse_diagram(fixture())
  let src = @mermaid.overview_source(d)
  @test.assert_eq(src.has_prefix("stateDiagram-v2\n    direction LR\n"), true)
  @test.assert_eq(
    src.contains("scan --> f1 : 0 actionable, 1 notice(s), parsed"),
    true,
  )
  @test.assert_eq(
    src.contains("scan --> f98 : 1 actionable, 2 notice(s), parsed"),
    true,
  )
  // the overview must not contain a composite state: that is what makes
  // dagre able to lay it out at all
  @test.assert_eq(src.contains(" as f1 {"), false)
}

///|
test "a file's sub-diagram keeps the source verbatim" {
  let d = @mermaid.parse_diagram(fixture())
  let src = @mermaid.file_source(d.files[1])
  @test.assert_eq(src.has_prefix("stateDiagram-v2\n    direction TB\n"), true)
  @test.assert_eq(
    src.contains(
      "state \"OperatorMismatch @6795:17 — unsupported operand types for '==': '[int]' and '[int]'\" as f98_e8",
    ),
    true,
  )
  @test.assert_eq(src.contains("note right of f98_e8"), true)
}

///|
test "the page is self contained and carries the data" {
  let d = @mermaid.parse_diagram(fixture())
  let page = @mermaid.render_page(d, "var mermaid = {};", "T", fixture())
  @test.assert_eq(page.has_prefix("<!DOCTYPE html>"), true)
  @test.assert_eq(page.contains("<title>T</title>"), true)
  @test.assert_eq(page.contains("id=\"files\""), true)
  @test.assert_eq(page.contains("id=\"overview-src\""), true)
  @test.assert_eq(page.contains("id=\"raw-src\""), true)
  @test.assert_eq(page.contains("var mermaid = {};"), true)
  @test.assert_eq(page.contains("riantr/moonbit_doubleML"), true)
}

///|
test "a closing script tag cannot escape the page" {
  let d = @mermaid.parse_diagram(fixture())
  let page = @mermaid.render_page(
    d,
    "var x = '</script><script>alert(1)</script>';",
    "T",
    fixture(),
  )
  // the raw </script> sequence must not appear inside the inlined runtime
  @test.assert_eq(page.contains("</script><script>alert(1)"), false)
}

///|
test "json escaping survives a round trip" {
  let s = "a\"b\\c\nd</script>"
  let esc = @mermaid.json_escape(s)
  @test.assert_eq(esc.contains("</script>"), false)
  @test.assert_eq(esc.contains("\\n"), true)
}

///|
/// A label with a character outside the basic plane is two UTF-16 code units
/// long, so every index after it shifts. The parser works in characters
/// throughout, and this is what proves it: before, the state was dropped.

///|
test "a label with a character outside the basic plane is parsed whole" {
  let lines = [
    "%% target=riantr/moonbit_doubleML files=1 parsed=1", "    scan --> f1 : 0 actionable, 1 notice(s), parsed",
    "    state \"f1 — a.mbt\" as f1 {", "        state \"🌙 moon\" as f1_n0",
    "    }",
  ]
  let d = @mermaid.parse_diagram(lines.join("\n"))
  @test.assert_eq(d.files.length(), 1)
  @test.assert_eq(d.files[0].states.length(), 1)
  @test.assert_eq(d.files[0].states[0].id, "f1_n0")
  @test.assert_eq(d.files[0].states[0].msg, "🌙 moon")
}

///|
/// The same, for the numbers on the edge label: they are read from a scan
/// over the characters, so they must be sliced with character indices too.

///|
test "a count behind a character outside the basic plane is still counted" {
  let lines = [
    "%% target=riantr/moonbit_doubleML files=1 parsed=1", "    scan --> f1 : 🌙 3 actionable, 4 notice(s), parsed",
    "    state \"f1 — a.mbt\" as f1 {", "        state \"lexed\" as f1_lex", "    }",
  ]
  let d = @mermaid.parse_diagram(lines.join("\n"))
  @test.assert_eq(d.files.length(), 1)
  @test.assert_eq(d.files[0].actionable, 3)
  @test.assert_eq(d.files[0].notice_count, 4)
}
