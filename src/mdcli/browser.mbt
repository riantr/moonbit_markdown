///|
/// Driving the headless browser.

///|
/// The browser is a rasteriser here: it renders the diagrams, and it turns
/// the laid-out sheets into a PDF. It decides nothing about the document -
/// which page holds what, how big a crop is, where a tick mark goes, is all
/// decided in MoonBit before the browser is started.
///
/// Chrome is driven through its command line rather than through a protocol
/// client, because the command line is enough for the two things that are
/// needed:
///
///   `--dump-dom`      renders a page and writes its DOM back as text, which
///                     is how the geometry of the drawings comes home;
///   `--print-to-pdf`  prints a laid-out page to a PDF.
///
/// Both wait for the page's own work: `--virtual-time-budget` keeps the
/// browser alive until the page has finished rendering its diagrams, so the
/// result is never a half-drawn document.

///|

///|
/// The flags every headless run needs.
///
fn base_flags() -> Array[String] {
  ["--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"]
}

///|
/// Is this an absolute Windows path?
///
fn is_absolute(path : String) -> Bool {
  if path.has_prefix("/") || path.has_prefix("\\") {
    return true
  }
  let cs = @text.chars(path)
  if cs.length() < 3 {
    return false
  }
  cs[0].is_ascii_alphabetic() && cs[1] == ':' && (cs[2] == '\\' || cs[2] == '/')
}

///|
/// The absolute path of a file.
///
/// Chrome's command line needs absolute paths. A relative `--print-to-pdf`
/// target is resolved against a directory of the browser's own choosing, and
/// the browser then writes nothing at all - and still reports success. The
/// same goes for the page to open: given a relative path the browser opens
/// nothing, so the measurement comes back empty.
///
/// So every path that goes to the browser is made absolute first.
///
pub fn absolute_path(path : String) -> String {
  if is_absolute(path) {
    return path
  }
  match @env.current_dir() {
    None => path
    Some(dir) => {
      let sep = if dir.has_suffix("\\") || dir.has_suffix("/") {
        ""
      } else {
        "\\"
      }
      dir + sep + path
    }
  }
}

///|
/// Render a page and read its DOM back as text.
///
pub async fn dump_dom(chrome : String, path : String) -> String? {
  let argv = base_flags()
  argv.push("--virtual-time-budget=300000")
  argv.push("--dump-dom")
  argv.push(absolute_path(path))
  let (code, out, err) = @process.collect_output(chrome, argv)
  if code != 0 {
    println("ERROR\tthe browser exited with \{code}")
    let e = err.text() catch { _ => "" }
    if !e.is_empty() {
      println(e)
    }
    return None
  }
  let dom = out.text() catch {
    e => {
      println("ERROR\tcannot read the browser's output: \{e}")
      return None
    }
  }
  Some(dom)
}

///|
/// Print a laid-out HTML page to a PDF with a headless browser.
///
/// The page is already laid out: the sheets are fixed size boxes, and the
/// browser only turns them into PDF pages. The page's own `@page` rule
/// decides the paper (A4 portrait) and the margins (12 mm), so the printed
/// sheets line up with the boxes the layout computed.
///
pub async fn print_to_pdf(
  in_path : String,
  out_path : String,
  chrome : String,
  header_footer : Bool,
) -> Unit {
  if !@fs.exists(chrome) {
    println("ERROR\tno browser at \{chrome}")
    return
  }
  let argv = base_flags()
  argv.push("--run-all-compositor-stages-before-draw")
  argv.push("--virtual-time-budget=600000")
  if !header_footer {
    argv.push("--no-pdf-header-footer")
  }
  argv.push("--print-to-pdf=" + absolute_path(out_path))
  argv.push(absolute_path(in_path))
  let (code, _out, err) = @process.collect_output(chrome, argv)
  if code != 0 {
    println("ERROR\tthe browser exited with \{code}")
    let e = err.text() catch { _ => "" }
    if !e.is_empty() {
      println(e)
    }
    return
  }
  if @fs.exists(out_path) {
    let size = @fs.file_size(out_path)
    println("wrote \{out_path} (\{size / 1024} KB)")
  } else {
    println("ERROR\tthe browser reported success but wrote no file")
  }
}
