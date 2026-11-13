///|
/// Page geometry for the figure-page mode.
///
/// In this mode the PDF does not use one paper size. Each diagram gets a sheet
/// of its own, sized so that the text inside the drawing prints at a chosen
/// size: one paper size for everything either wastes the small figures or
/// shrinks the large ones past reading.
///
/// The lever is CSS. This toolchain prints through a headless browser whose
/// paper comes from the page's own `@page` rule, and CSS named pages give one
/// rule per figure, so the sheet can differ from page to page inside a single
/// PDF. The sizes are computed here, in MoonBit, and handed over as one more
/// stylesheet fragment - the browser still decides nothing.

///|
/// One CSS pixel in millimetres, at the 96 dpi the browser lays out at.
pub const MM_PER_PX : Double = 0.2645833333333333

///|
/// One CSS pixel in points: 72 pt to the inch, 96 px to the inch.
pub const PT_PER_PX : Double = 0.75

///|
/// The margin a figure page gives its drawing, in millimetres.
///
/// Smaller than the 12 mm of a text page on purpose: a figure page carries one
/// picture and nothing else, so the margin only has to keep the drawing off
/// the paper's edge.
pub const FIGURE_MARGIN_MM : Double = 8.0

///|
/// The slack left between the drawing's box and the printable area.
///
/// A box the exact size of the printable area is the obvious thing to ask for
/// and it does not survive: the figure ends up a hair over the sheet, breaks
/// across two of them, and a figure that spans pages stops being given the
/// sheet it asked for - measured, not guessed. So the box is short by this
/// much, and the sheet is sized with it added back, which keeps the promised
/// label size instead of quietly delivering 87 % of it.
pub const FIGURE_SLACK_MM : Double = 4.0

///|
/// The paper a named size stands for, in millimetres.
///
/// A6 is the floor for a figure page: a drawing can be smaller than a sheet,
/// but a page that is not page-sized reads as a mistake. A0 is the ceiling for
/// the same reason - past it the sheet is a poster, not a page.
pub fn paper_size(spec : String) -> (Double, Double)? {
  if spec == "A6" {
    Some((105.0, 148.0))
  } else if spec == "A5" {
    Some((148.0, 210.0))
  } else if spec == "A4" {
    Some((210.0, 297.0))
  } else if spec == "A3" {
    Some((297.0, 420.0))
  } else if spec == "A2" {
    Some((420.0, 594.0))
  } else if spec == "A1" {
    Some((594.0, 841.0))
  } else if spec == "A0" {
    Some((841.0, 1189.0))
  } else {
    None
  }
}

///|
/// A number of millimetres, written the way the CSS wants it.
fn number_mm(s : String) -> Double? {
  let cs = @tx.chars(s)
  let n = cs.length()
  let mut i = 0
  let mut value = 0.0
  let mut digits = 0
  while i < n && cs[i] >= '0' && cs[i] <= '9' {
    value = value * 10.0 + (cs[i].to_int() - 48).to_double()
    digits += 1
    i += 1
  }
  if digits == 0 {
    return None
  }
  if i < n && cs[i] == '.' {
    i += 1
    let mut scale = 0.1
    let mut frac = 0
    while i < n && cs[i] >= '0' && cs[i] <= '9' {
      value = value + (cs[i].to_int() - 48).to_double() * scale
      scale = scale * 0.1
      i += 1
      frac += 1
    }
    if frac == 0 {
      return None
    }
  }
  if i < n {
    // the only suffix a size may carry is "mm"; anything else is a typo, and
    // reporting it is better than silently reading the digits and ignoring the
    // rest
    if i + 2 != n || cs[i] != 'm' || cs[i + 1] != 'm' {
      return None
    }
  }
  if value <= 0.0 {
    return None
  }
  Some(value)
}

///|
/// A paper size: a name (`A4` ... `A0`) or an explicit `<w>x<h>mm`.
///
/// The explicit form exists because the useful sizes for a drawing are not
/// always the paper sizes: 300 x 400 mm is a real answer for a wide diagram
/// and no A-series sheet is.
pub fn paper_of(spec : String) -> (Double, Double)? {
  match paper_size(spec) {
    Some(p) => Some(p)
    None => {
      let cs = @tx.chars(spec)
      let n = cs.length()
      let mut cut = -1
      let mut i = 0
      while i < n {
        if cs[i] == 'x' || cs[i] == 'X' {
          cut = i
          break
        }
        i += 1
      }
      if cut <= 0 {
        None
      } else {
        match (number_mm(spec[0:cut].to_owned()), number_mm(spec[cut + 1:n].to_owned())) {
          (Some(w), Some(h)) => Some((w, h))
          _ => None
        }
      }
    }
  }
}

///|
/// The sheet computed for one diagram.
pub struct FigurePage {
  /// which figure of the document this sheet belongs to, as `data-fig`
  index : Int
  /// the sheet, in millimetres
  width_mm : Double
  height_mm : Double
  /// the scale the drawing ends up printed at
  scale : Double
  /// the size its labels end up printed at
  label_pt : Double
  /// true when the sheet is smaller than the drawing asked for
  capped : Bool
}

///|
fn clamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Size one sheet per diagram.
///
/// The arithmetic is the drawing's own: a label that measures `font` CSS px in
/// the diagram prints at `font * 0.75` pt when the drawing is printed at 1:1,
/// so the scale that lands it on `target_pt` is `target_pt / (font * 0.75)`.
/// The sheet that scale needs is the drawing's size times the scale, plus the
/// margins. Two clamps follow: never enlarge a drawing past the size it was
/// written at, and never leave the `min`/`max` paper range.
///
/// The reported size follows the sheet rather than the wish, because a drawing
/// is bounded by its box and never stretched to fill it: the printed scale is
/// the smaller of 1:1 and what the box allows. A drawing whose labels are
/// already larger than the target, and whose sheet was raised to the minimum
/// paper, therefore prints at its own size - above the target, which is the
/// harmless direction, but stated rather than smoothed over. When the `max`
/// bites, the sheet is the cap and the labels come out below the target, which
/// is the one case this mode cannot deliver - so it is reported per figure
/// rather than left to be discovered.
pub fn figure_pages(
  dims : Array[(Double, Double)],
  fonts : Array[Double],
  target_pt : Double,
  max_mm : (Double, Double),
  min_mm : (Double, Double),
  margin_mm : Double,
) -> Array[FigurePage] {
  let out : Array[FigurePage] = []
  for i in 0..<dims.length() {
    let (w_px, h_px) = dims[i]
    if w_px <= 0.0 || h_px <= 0.0 {
      // a diagram that did not render has no size to honour: it keeps the
      // default sheet and shows its error there
      continue
    }
    let font = if i < fonts.length() && fonts[i] > 0.0 {
      fonts[i]
    } else {
      // Mermaid's default label size, for a document measured without it
      16.0
    }
    let mut s = target_pt / (font * PT_PER_PX)
    if s > 1.0 {
      s = 1.0
    }
    let draw_w = w_px * MM_PER_PX
    let draw_h = h_px * MM_PER_PX
    let want_w = draw_w * s + 2.0 * margin_mm + FIGURE_SLACK_MM
    let want_h = draw_h * s + 2.0 * margin_mm + FIGURE_SLACK_MM
    let w = clamp(want_w, min_mm.0, max_mm.0)
    let h = clamp(want_h, min_mm.1, max_mm.1)
    let fit_w = (w - 2.0 * margin_mm - FIGURE_SLACK_MM) / draw_w
    let fit_h = (h - 2.0 * margin_mm - FIGURE_SLACK_MM) / draw_h
    // What prints is the drawing bounded by the sheet, not the scale the sheet
    // was computed for: the browser only ever shrinks a drawing, it never
    // enlarges it, so a sheet that ended up on the minimum paper and is larger
    // than the drawing holds it at its own size. Asking for 6 pt of a drawing
    // whose labels are 12 pt at 1:1 then prints 12 pt, and a report that said 6
    // would be a prediction rather than a measurement.
    let mut eff = 1.0
    if fit_w < eff {
      eff = fit_w
    }
    if fit_h < eff {
      eff = fit_h
    }
    if eff < 0.0 {
      eff = 0.0
    }
    out.push({
      index: i,
      width_mm: w,
      height_mm: h,
      scale: eff,
      label_pt: font * PT_PER_PX * eff,
      capped: want_w - w > 0.01 || want_h - h > 0.01,
    })
  }
  out
}

///|
/// A length in millimetres, one decimal, as CSS wants it.
fn mm_text(mm : Double) -> String {
  let tenths = (mm * 10.0 + 0.5).to_int()
  let whole = tenths / 10
  let frac = tenths % 10
  let sb = StringBuilder()
  sb.write_string(whole.to_string())
  sb.write_string(".")
  sb.write_string(frac.to_string())
  sb.write_string("mm")
  sb.to_string()
}

///|
/// The stylesheet that gives each figure its own sheet.
///
/// One `@page` rule per figure, plus a `page:` declaration that selects it, and
/// the drawing's height set to the sheet's content height so the flex box that
/// centres it is exactly the printable area.
pub fn figure_page_css(pages : Array[FigurePage], margin_mm : Double) -> String {
  let sb = StringBuilder()
  if pages.is_empty() {
    return ""
  }
  sb.write_string("@media print{\n")
  // The block this mode replaces, not adds to: the one-page stylesheet gives
  // every drawing a fixed 265 mm box and caps its svg at that height, which is
  // right for a uniform A4 sheet and wrong here - with both blocks present the
  // browser stops honouring the named page and prints the figure on A4 across
  // two pages. So this mode carries the whole block itself.
  sb.write_string(
    "main.figures-one-page .mermaid{break-before:page;break-after:page;page-break-before:always;page-break-after:always;display:flex;align-items:center;justify-content:center;margin:0;overflow:hidden}\n",
  )
  for p in pages {
    let n = p.index.to_string()
    sb.write_string("@page fig")
    sb.write_string(n)
    sb.write_string("{size:")
    sb.write_string(mm_text(p.width_mm))
    sb.write_string(" ")
    sb.write_string(mm_text(p.height_mm))
    sb.write_string(";margin:")
    sb.write_string(mm_text(margin_mm))
    sb.write_string("}\n")
    sb.write_string("main.figures-one-page [data-fig=\"")
    sb.write_string(n)
    sb.write_string("\"]{page:fig")
    sb.write_string(n)
    sb.write_string(";height:")
    sb.write_string(mm_text(p.height_mm - 2.0 * margin_mm - FIGURE_SLACK_MM))
    sb.write_string("}\n")
    // The drawing is bounded on both axes and keeps its own ratio. Both bounds
    // are needed: `width:100%` alone makes a tall drawing taller than the
    // sheet, and the browser then drops the named page - measured, not
    // guessed. What this costs is stated in the README: the drawing lands
    // inside the box rather than filling it, so the labels come out around
    // 0.87 of the size the sheet was computed for.
    sb.write_string("main.figures-one-page [data-fig=\"")
    sb.write_string(n)
    sb.write_string("\"] svg{width:auto!important;height:auto!important;")
    sb.write_string("max-width:100%!important;max-height:100%!important}\n")
  }
  sb.write_string("}")
  sb.to_string()
}
