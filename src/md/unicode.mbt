///|
/// The Unicode character classes the Markdown parser needs.
///
/// CommonMark defines a *Unicode whitespace character* as a character
/// in the Unicode `Zs` general category, or a tab, a line feed, a form
/// feed or a carriage return; and a *Unicode punctuation character* as a
/// character in the Unicode `P` or `S` general categories. The ASCII
/// helpers in src/text cannot express either, and the distinction
/// matters: `*£*bravo.` is not emphasis, because `£` is a symbol and
/// therefore punctuation for this purpose.
///
/// The tables are generated - see tools/gen_unicode_table.py.

///|
/// Is the character a Unicode whitespace character?
///
pub fn is_unicode_whitespace(c : Char) -> Bool {
  whitespace(c.to_int())
}

///|
/// Is the character a Unicode punctuation character (the `P` and `S`
/// general categories)?
///
pub fn is_unicode_punctuation(c : Char) -> Bool {
  punct_symbol(c.to_int())
}

///|
/// The ranges of the whitespace class, split over 1 function so that no
/// single one of them is large enough to overflow the native C parser.
///

///|
fn whitespace_0(u : Int32) -> Bool {
  if u >= 0x9 && u <= 0xA {
    return true
  }
  if u >= 0xC && u <= 0xD {
    return true
  }
  if u == 0x20 {
    return true
  }
  if u == 0xA0 {
    return true
  }
  if u == 0x1680 {
    return true
  }
  if u >= 0x2000 && u <= 0x200A {
    return true
  }
  if u == 0x202F {
    return true
  }
  if u == 0x205F {
    return true
  }
  if u == 0x3000 {
    return true
  }
  false
}

///|
fn whitespace(u : Int32) -> Bool {
  if whitespace_0(u) {
    return true
  }
  false
}

///|
/// The ranges of the punct_symbol class, split over 9 functions so that no
/// single one of them is large enough to overflow the native C parser.
///

///|
fn punct_symbol_0(u : Int32) -> Bool {
  if u >= 0x21 && u <= 0x2F {
    return true
  }
  if u >= 0x3A && u <= 0x40 {
    return true
  }
  if u >= 0x5B && u <= 0x60 {
    return true
  }
  if u >= 0x7B && u <= 0x7E {
    return true
  }
  if u >= 0xA1 && u <= 0xA9 {
    return true
  }
  if u >= 0xAB && u <= 0xAC {
    return true
  }
  if u >= 0xAE && u <= 0xB1 {
    return true
  }
  if u == 0xB4 {
    return true
  }
  if u >= 0xB6 && u <= 0xB8 {
    return true
  }
  if u == 0xBB {
    return true
  }
  if u == 0xBF {
    return true
  }
  if u == 0xD7 {
    return true
  }
  if u == 0xF7 {
    return true
  }
  if u >= 0x2C2 && u <= 0x2C5 {
    return true
  }
  if u >= 0x2D2 && u <= 0x2DF {
    return true
  }
  if u >= 0x2E5 && u <= 0x2EB {
    return true
  }
  if u == 0x2ED {
    return true
  }
  if u >= 0x2EF && u <= 0x2FF {
    return true
  }
  if u == 0x375 {
    return true
  }
  if u == 0x37E {
    return true
  }
  if u >= 0x384 && u <= 0x385 {
    return true
  }
  if u == 0x387 {
    return true
  }
  if u == 0x3F6 {
    return true
  }
  if u == 0x482 {
    return true
  }
  if u >= 0x55A && u <= 0x55F {
    return true
  }
  if u >= 0x589 && u <= 0x58A {
    return true
  }
  if u >= 0x58D && u <= 0x58F {
    return true
  }
  if u == 0x5BE {
    return true
  }
  if u == 0x5C0 {
    return true
  }
  if u == 0x5C3 {
    return true
  }
  if u == 0x5C6 {
    return true
  }
  if u >= 0x5F3 && u <= 0x5F4 {
    return true
  }
  if u >= 0x606 && u <= 0x60F {
    return true
  }
  if u == 0x61B {
    return true
  }
  if u >= 0x61D && u <= 0x61F {
    return true
  }
  if u >= 0x66A && u <= 0x66D {
    return true
  }
  if u == 0x6D4 {
    return true
  }
  if u == 0x6DE {
    return true
  }
  if u == 0x6E9 {
    return true
  }
  if u >= 0x6FD && u <= 0x6FE {
    return true
  }
  false
}

///|
fn punct_symbol_1(u : Int32) -> Bool {
  if u >= 0x700 && u <= 0x70D {
    return true
  }
  if u >= 0x7F6 && u <= 0x7F9 {
    return true
  }
  if u >= 0x7FE && u <= 0x7FF {
    return true
  }
  if u >= 0x830 && u <= 0x83E {
    return true
  }
  if u == 0x85E {
    return true
  }
  if u == 0x888 {
    return true
  }
  if u >= 0x964 && u <= 0x965 {
    return true
  }
  if u == 0x970 {
    return true
  }
  if u >= 0x9F2 && u <= 0x9F3 {
    return true
  }
  if u >= 0x9FA && u <= 0x9FB {
    return true
  }
  if u == 0x9FD {
    return true
  }
  if u == 0xA76 {
    return true
  }
  if u >= 0xAF0 && u <= 0xAF1 {
    return true
  }
  if u == 0xB70 {
    return true
  }
  if u >= 0xBF3 && u <= 0xBFA {
    return true
  }
  if u == 0xC77 {
    return true
  }
  if u == 0xC7F {
    return true
  }
  if u == 0xC84 {
    return true
  }
  if u == 0xD4F {
    return true
  }
  if u == 0xD79 {
    return true
  }
  if u == 0xDF4 {
    return true
  }
  if u == 0xE3F {
    return true
  }
  if u == 0xE4F {
    return true
  }
  if u >= 0xE5A && u <= 0xE5B {
    return true
  }
  if u >= 0xF01 && u <= 0xF17 {
    return true
  }
  if u >= 0xF1A && u <= 0xF1F {
    return true
  }
  if u == 0xF34 {
    return true
  }
  if u == 0xF36 {
    return true
  }
  if u == 0xF38 {
    return true
  }
  if u >= 0xF3A && u <= 0xF3D {
    return true
  }
  if u == 0xF85 {
    return true
  }
  if u >= 0xFBE && u <= 0xFC5 {
    return true
  }
  if u >= 0xFC7 && u <= 0xFCC {
    return true
  }
  if u >= 0xFCE && u <= 0xFDA {
    return true
  }
  if u >= 0x104A && u <= 0x104F {
    return true
  }
  if u >= 0x109E && u <= 0x109F {
    return true
  }
  if u == 0x10FB {
    return true
  }
  if u >= 0x1360 && u <= 0x1368 {
    return true
  }
  if u >= 0x1390 && u <= 0x1399 {
    return true
  }
  if u == 0x1400 {
    return true
  }
  false
}

///|
fn punct_symbol_2(u : Int32) -> Bool {
  if u >= 0x166D && u <= 0x166E {
    return true
  }
  if u >= 0x169B && u <= 0x169C {
    return true
  }
  if u >= 0x16EB && u <= 0x16ED {
    return true
  }
  if u >= 0x1735 && u <= 0x1736 {
    return true
  }
  if u >= 0x17D4 && u <= 0x17D6 {
    return true
  }
  if u >= 0x17D8 && u <= 0x17DB {
    return true
  }
  if u >= 0x1800 && u <= 0x180A {
    return true
  }
  if u == 0x1940 {
    return true
  }
  if u >= 0x1944 && u <= 0x1945 {
    return true
  }
  if u >= 0x19DE && u <= 0x19FF {
    return true
  }
  if u >= 0x1A1E && u <= 0x1A1F {
    return true
  }
  if u >= 0x1AA0 && u <= 0x1AA6 {
    return true
  }
  if u >= 0x1AA8 && u <= 0x1AAD {
    return true
  }
  if u >= 0x1B5A && u <= 0x1B6A {
    return true
  }
  if u >= 0x1B74 && u <= 0x1B7E {
    return true
  }
  if u >= 0x1BFC && u <= 0x1BFF {
    return true
  }
  if u >= 0x1C3B && u <= 0x1C3F {
    return true
  }
  if u >= 0x1C7E && u <= 0x1C7F {
    return true
  }
  if u >= 0x1CC0 && u <= 0x1CC7 {
    return true
  }
  if u == 0x1CD3 {
    return true
  }
  if u == 0x1FBD {
    return true
  }
  if u >= 0x1FBF && u <= 0x1FC1 {
    return true
  }
  if u >= 0x1FCD && u <= 0x1FCF {
    return true
  }
  if u >= 0x1FDD && u <= 0x1FDF {
    return true
  }
  if u >= 0x1FED && u <= 0x1FEF {
    return true
  }
  if u >= 0x1FFD && u <= 0x1FFE {
    return true
  }
  if u >= 0x2010 && u <= 0x2027 {
    return true
  }
  if u >= 0x2030 && u <= 0x205E {
    return true
  }
  if u >= 0x207A && u <= 0x207E {
    return true
  }
  if u >= 0x208A && u <= 0x208E {
    return true
  }
  if u >= 0x20A0 && u <= 0x20C0 {
    return true
  }
  if u >= 0x2100 && u <= 0x2101 {
    return true
  }
  if u >= 0x2103 && u <= 0x2106 {
    return true
  }
  if u >= 0x2108 && u <= 0x2109 {
    return true
  }
  if u == 0x2114 {
    return true
  }
  if u >= 0x2116 && u <= 0x2118 {
    return true
  }
  if u >= 0x211E && u <= 0x2123 {
    return true
  }
  if u == 0x2125 {
    return true
  }
  if u == 0x2127 {
    return true
  }
  if u == 0x2129 {
    return true
  }
  false
}

///|
fn punct_symbol_3(u : Int32) -> Bool {
  if u == 0x212E {
    return true
  }
  if u >= 0x213A && u <= 0x213B {
    return true
  }
  if u >= 0x2140 && u <= 0x2144 {
    return true
  }
  if u >= 0x214A && u <= 0x214D {
    return true
  }
  if u == 0x214F {
    return true
  }
  if u >= 0x218A && u <= 0x218B {
    return true
  }
  if u >= 0x2190 && u <= 0x2426 {
    return true
  }
  if u >= 0x2440 && u <= 0x244A {
    return true
  }
  if u >= 0x249C && u <= 0x24E9 {
    return true
  }
  if u >= 0x2500 && u <= 0x2775 {
    return true
  }
  if u >= 0x2794 && u <= 0x2B73 {
    return true
  }
  if u >= 0x2B76 && u <= 0x2B95 {
    return true
  }
  if u >= 0x2B97 && u <= 0x2BFF {
    return true
  }
  if u >= 0x2CE5 && u <= 0x2CEA {
    return true
  }
  if u >= 0x2CF9 && u <= 0x2CFC {
    return true
  }
  if u >= 0x2CFE && u <= 0x2CFF {
    return true
  }
  if u == 0x2D70 {
    return true
  }
  if u >= 0x2E00 && u <= 0x2E2E {
    return true
  }
  if u >= 0x2E30 && u <= 0x2E5D {
    return true
  }
  if u >= 0x2E80 && u <= 0x2E99 {
    return true
  }
  if u >= 0x2E9B && u <= 0x2EF3 {
    return true
  }
  if u >= 0x2F00 && u <= 0x2FD5 {
    return true
  }
  if u >= 0x2FF0 && u <= 0x2FFF {
    return true
  }
  if u >= 0x3001 && u <= 0x3004 {
    return true
  }
  if u >= 0x3008 && u <= 0x3020 {
    return true
  }
  if u == 0x3030 {
    return true
  }
  if u >= 0x3036 && u <= 0x3037 {
    return true
  }
  if u >= 0x303D && u <= 0x303F {
    return true
  }
  if u >= 0x309B && u <= 0x309C {
    return true
  }
  if u == 0x30A0 {
    return true
  }
  if u == 0x30FB {
    return true
  }
  if u >= 0x3190 && u <= 0x3191 {
    return true
  }
  if u >= 0x3196 && u <= 0x319F {
    return true
  }
  if u >= 0x31C0 && u <= 0x31E3 {
    return true
  }
  if u == 0x31EF {
    return true
  }
  if u >= 0x3200 && u <= 0x321E {
    return true
  }
  if u >= 0x322A && u <= 0x3247 {
    return true
  }
  if u == 0x3250 {
    return true
  }
  if u >= 0x3260 && u <= 0x327F {
    return true
  }
  if u >= 0x328A && u <= 0x32B0 {
    return true
  }
  false
}

///|
fn punct_symbol_4(u : Int32) -> Bool {
  if u >= 0x32C0 && u <= 0x33FF {
    return true
  }
  if u >= 0x4DC0 && u <= 0x4DFF {
    return true
  }
  if u >= 0xA490 && u <= 0xA4C6 {
    return true
  }
  if u >= 0xA4FE && u <= 0xA4FF {
    return true
  }
  if u >= 0xA60D && u <= 0xA60F {
    return true
  }
  if u == 0xA673 {
    return true
  }
  if u == 0xA67E {
    return true
  }
  if u >= 0xA6F2 && u <= 0xA6F7 {
    return true
  }
  if u >= 0xA700 && u <= 0xA716 {
    return true
  }
  if u >= 0xA720 && u <= 0xA721 {
    return true
  }
  if u >= 0xA789 && u <= 0xA78A {
    return true
  }
  if u >= 0xA828 && u <= 0xA82B {
    return true
  }
  if u >= 0xA836 && u <= 0xA839 {
    return true
  }
  if u >= 0xA874 && u <= 0xA877 {
    return true
  }
  if u >= 0xA8CE && u <= 0xA8CF {
    return true
  }
  if u >= 0xA8F8 && u <= 0xA8FA {
    return true
  }
  if u == 0xA8FC {
    return true
  }
  if u >= 0xA92E && u <= 0xA92F {
    return true
  }
  if u == 0xA95F {
    return true
  }
  if u >= 0xA9C1 && u <= 0xA9CD {
    return true
  }
  if u >= 0xA9DE && u <= 0xA9DF {
    return true
  }
  if u >= 0xAA5C && u <= 0xAA5F {
    return true
  }
  if u >= 0xAA77 && u <= 0xAA79 {
    return true
  }
  if u >= 0xAADE && u <= 0xAADF {
    return true
  }
  if u >= 0xAAF0 && u <= 0xAAF1 {
    return true
  }
  if u == 0xAB5B {
    return true
  }
  if u >= 0xAB6A && u <= 0xAB6B {
    return true
  }
  if u == 0xABEB {
    return true
  }
  if u == 0xFB29 {
    return true
  }
  if u >= 0xFBB2 && u <= 0xFBC2 {
    return true
  }
  if u >= 0xFD3E && u <= 0xFD4F {
    return true
  }
  if u == 0xFDCF {
    return true
  }
  if u >= 0xFDFC && u <= 0xFDFF {
    return true
  }
  if u >= 0xFE10 && u <= 0xFE19 {
    return true
  }
  if u >= 0xFE30 && u <= 0xFE52 {
    return true
  }
  if u >= 0xFE54 && u <= 0xFE66 {
    return true
  }
  if u >= 0xFE68 && u <= 0xFE6B {
    return true
  }
  if u >= 0xFF01 && u <= 0xFF0F {
    return true
  }
  if u >= 0xFF1A && u <= 0xFF20 {
    return true
  }
  if u >= 0xFF3B && u <= 0xFF40 {
    return true
  }
  false
}

///|
fn punct_symbol_5(u : Int32) -> Bool {
  if u >= 0xFF5B && u <= 0xFF65 {
    return true
  }
  if u >= 0xFFE0 && u <= 0xFFE6 {
    return true
  }
  if u >= 0xFFE8 && u <= 0xFFEE {
    return true
  }
  if u >= 0xFFFC && u <= 0xFFFD {
    return true
  }
  if u >= 0x10100 && u <= 0x10102 {
    return true
  }
  if u >= 0x10137 && u <= 0x1013F {
    return true
  }
  if u >= 0x10179 && u <= 0x10189 {
    return true
  }
  if u >= 0x1018C && u <= 0x1018E {
    return true
  }
  if u >= 0x10190 && u <= 0x1019C {
    return true
  }
  if u == 0x101A0 {
    return true
  }
  if u >= 0x101D0 && u <= 0x101FC {
    return true
  }
  if u == 0x1039F {
    return true
  }
  if u == 0x103D0 {
    return true
  }
  if u == 0x1056F {
    return true
  }
  if u == 0x10857 {
    return true
  }
  if u >= 0x10877 && u <= 0x10878 {
    return true
  }
  if u == 0x1091F {
    return true
  }
  if u == 0x1093F {
    return true
  }
  if u >= 0x10A50 && u <= 0x10A58 {
    return true
  }
  if u == 0x10A7F {
    return true
  }
  if u == 0x10AC8 {
    return true
  }
  if u >= 0x10AF0 && u <= 0x10AF6 {
    return true
  }
  if u >= 0x10B39 && u <= 0x10B3F {
    return true
  }
  if u >= 0x10B99 && u <= 0x10B9C {
    return true
  }
  if u == 0x10EAD {
    return true
  }
  if u >= 0x10F55 && u <= 0x10F59 {
    return true
  }
  if u >= 0x10F86 && u <= 0x10F89 {
    return true
  }
  if u >= 0x11047 && u <= 0x1104D {
    return true
  }
  if u >= 0x110BB && u <= 0x110BC {
    return true
  }
  if u >= 0x110BE && u <= 0x110C1 {
    return true
  }
  if u >= 0x11140 && u <= 0x11143 {
    return true
  }
  if u >= 0x11174 && u <= 0x11175 {
    return true
  }
  if u >= 0x111C5 && u <= 0x111C8 {
    return true
  }
  if u == 0x111CD {
    return true
  }
  if u == 0x111DB {
    return true
  }
  if u >= 0x111DD && u <= 0x111DF {
    return true
  }
  if u >= 0x11238 && u <= 0x1123D {
    return true
  }
  if u == 0x112A9 {
    return true
  }
  if u >= 0x1144B && u <= 0x1144F {
    return true
  }
  if u >= 0x1145A && u <= 0x1145B {
    return true
  }
  false
}

///|
fn punct_symbol_6(u : Int32) -> Bool {
  if u == 0x1145D {
    return true
  }
  if u == 0x114C6 {
    return true
  }
  if u >= 0x115C1 && u <= 0x115D7 {
    return true
  }
  if u >= 0x11641 && u <= 0x11643 {
    return true
  }
  if u >= 0x11660 && u <= 0x1166C {
    return true
  }
  if u == 0x116B9 {
    return true
  }
  if u >= 0x1173C && u <= 0x1173F {
    return true
  }
  if u == 0x1183B {
    return true
  }
  if u >= 0x11944 && u <= 0x11946 {
    return true
  }
  if u == 0x119E2 {
    return true
  }
  if u >= 0x11A3F && u <= 0x11A46 {
    return true
  }
  if u >= 0x11A9A && u <= 0x11A9C {
    return true
  }
  if u >= 0x11A9E && u <= 0x11AA2 {
    return true
  }
  if u >= 0x11B00 && u <= 0x11B09 {
    return true
  }
  if u >= 0x11C41 && u <= 0x11C45 {
    return true
  }
  if u >= 0x11C70 && u <= 0x11C71 {
    return true
  }
  if u >= 0x11EF7 && u <= 0x11EF8 {
    return true
  }
  if u >= 0x11F43 && u <= 0x11F4F {
    return true
  }
  if u >= 0x11FD5 && u <= 0x11FF1 {
    return true
  }
  if u == 0x11FFF {
    return true
  }
  if u >= 0x12470 && u <= 0x12474 {
    return true
  }
  if u >= 0x12FF1 && u <= 0x12FF2 {
    return true
  }
  if u >= 0x16A6E && u <= 0x16A6F {
    return true
  }
  if u == 0x16AF5 {
    return true
  }
  if u >= 0x16B37 && u <= 0x16B3F {
    return true
  }
  if u >= 0x16B44 && u <= 0x16B45 {
    return true
  }
  if u >= 0x16E97 && u <= 0x16E9A {
    return true
  }
  if u == 0x16FE2 {
    return true
  }
  if u == 0x1BC9C {
    return true
  }
  if u == 0x1BC9F {
    return true
  }
  if u >= 0x1CF50 && u <= 0x1CFC3 {
    return true
  }
  if u >= 0x1D000 && u <= 0x1D0F5 {
    return true
  }
  if u >= 0x1D100 && u <= 0x1D126 {
    return true
  }
  if u >= 0x1D129 && u <= 0x1D164 {
    return true
  }
  if u >= 0x1D16A && u <= 0x1D16C {
    return true
  }
  if u >= 0x1D183 && u <= 0x1D184 {
    return true
  }
  if u >= 0x1D18C && u <= 0x1D1A9 {
    return true
  }
  if u >= 0x1D1AE && u <= 0x1D1EA {
    return true
  }
  if u >= 0x1D200 && u <= 0x1D241 {
    return true
  }
  if u == 0x1D245 {
    return true
  }
  false
}

///|
fn punct_symbol_7(u : Int32) -> Bool {
  if u >= 0x1D300 && u <= 0x1D356 {
    return true
  }
  if u == 0x1D6C1 {
    return true
  }
  if u == 0x1D6DB {
    return true
  }
  if u == 0x1D6FB {
    return true
  }
  if u == 0x1D715 {
    return true
  }
  if u == 0x1D735 {
    return true
  }
  if u == 0x1D74F {
    return true
  }
  if u == 0x1D76F {
    return true
  }
  if u == 0x1D789 {
    return true
  }
  if u == 0x1D7A9 {
    return true
  }
  if u == 0x1D7C3 {
    return true
  }
  if u >= 0x1D800 && u <= 0x1D9FF {
    return true
  }
  if u >= 0x1DA37 && u <= 0x1DA3A {
    return true
  }
  if u >= 0x1DA6D && u <= 0x1DA74 {
    return true
  }
  if u >= 0x1DA76 && u <= 0x1DA83 {
    return true
  }
  if u >= 0x1DA85 && u <= 0x1DA8B {
    return true
  }
  if u == 0x1E14F {
    return true
  }
  if u == 0x1E2FF {
    return true
  }
  if u >= 0x1E95E && u <= 0x1E95F {
    return true
  }
  if u == 0x1ECAC {
    return true
  }
  if u == 0x1ECB0 {
    return true
  }
  if u == 0x1ED2E {
    return true
  }
  if u >= 0x1EEF0 && u <= 0x1EEF1 {
    return true
  }
  if u >= 0x1F000 && u <= 0x1F02B {
    return true
  }
  if u >= 0x1F030 && u <= 0x1F093 {
    return true
  }
  if u >= 0x1F0A0 && u <= 0x1F0AE {
    return true
  }
  if u >= 0x1F0B1 && u <= 0x1F0BF {
    return true
  }
  if u >= 0x1F0C1 && u <= 0x1F0CF {
    return true
  }
  if u >= 0x1F0D1 && u <= 0x1F0F5 {
    return true
  }
  if u >= 0x1F10D && u <= 0x1F1AD {
    return true
  }
  if u >= 0x1F1E6 && u <= 0x1F202 {
    return true
  }
  if u >= 0x1F210 && u <= 0x1F23B {
    return true
  }
  if u >= 0x1F240 && u <= 0x1F248 {
    return true
  }
  if u >= 0x1F250 && u <= 0x1F251 {
    return true
  }
  if u >= 0x1F260 && u <= 0x1F265 {
    return true
  }
  if u >= 0x1F300 && u <= 0x1F6D7 {
    return true
  }
  if u >= 0x1F6DC && u <= 0x1F6EC {
    return true
  }
  if u >= 0x1F6F0 && u <= 0x1F6FC {
    return true
  }
  if u >= 0x1F700 && u <= 0x1F776 {
    return true
  }
  if u >= 0x1F77B && u <= 0x1F7D9 {
    return true
  }
  false
}

///|
fn punct_symbol_8(u : Int32) -> Bool {
  if u >= 0x1F7E0 && u <= 0x1F7EB {
    return true
  }
  if u == 0x1F7F0 {
    return true
  }
  if u >= 0x1F800 && u <= 0x1F80B {
    return true
  }
  if u >= 0x1F810 && u <= 0x1F847 {
    return true
  }
  if u >= 0x1F850 && u <= 0x1F859 {
    return true
  }
  if u >= 0x1F860 && u <= 0x1F887 {
    return true
  }
  if u >= 0x1F890 && u <= 0x1F8AD {
    return true
  }
  if u >= 0x1F8B0 && u <= 0x1F8B1 {
    return true
  }
  if u >= 0x1F900 && u <= 0x1FA53 {
    return true
  }
  if u >= 0x1FA60 && u <= 0x1FA6D {
    return true
  }
  if u >= 0x1FA70 && u <= 0x1FA7C {
    return true
  }
  if u >= 0x1FA80 && u <= 0x1FA88 {
    return true
  }
  if u >= 0x1FA90 && u <= 0x1FABD {
    return true
  }
  if u >= 0x1FABF && u <= 0x1FAC5 {
    return true
  }
  if u >= 0x1FACE && u <= 0x1FADB {
    return true
  }
  if u >= 0x1FAE0 && u <= 0x1FAE8 {
    return true
  }
  if u >= 0x1FAF0 && u <= 0x1FAF8 {
    return true
  }
  if u >= 0x1FB00 && u <= 0x1FB92 {
    return true
  }
  if u >= 0x1FB94 && u <= 0x1FBCA {
    return true
  }
  false
}

///|
fn punct_symbol(u : Int32) -> Bool {
  if punct_symbol_0(u) {
    return true
  }
  if punct_symbol_1(u) {
    return true
  }
  if punct_symbol_2(u) {
    return true
  }
  if punct_symbol_3(u) {
    return true
  }
  if punct_symbol_4(u) {
    return true
  }
  if punct_symbol_5(u) {
    return true
  }
  if punct_symbol_6(u) {
    return true
  }
  if punct_symbol_7(u) {
    return true
  }
  if punct_symbol_8(u) {
    return true
  }
  false
}
