#!/usr/bin/env python3
"""Generate the Unicode character-class tables the Markdown parser needs.

CommonMark defines two character classes that the ASCII-only helpers in
src/text cannot express:

  * a *Unicode whitespace character* is a character in the Unicode `Zs`
    general category, or a tab (U+0009), line feed (U+000A), form feed
    (U+000C) or carriage return (U+000D);

  * a *Unicode punctuation character* is a character in the Unicode `P`
    (punctuation) or `S` (symbol) general categories.

The tables are ranges, and the ranges are long, so the generator splits them
over several functions: one enormous `match` would overflow MSVC's C parser
(the same failure the entity table had).

    python tools/gen_unicode_table.py

The result is src/md/unicode.mbt, which is part of the package.
"""

import os
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'src', 'md', 'unicode.mbt')

# The ranges are split into functions of at most this many entries, so that no
# single function is large enough to overflow the native C parser.
PER_FUNCTION = 40

WHITESPACE_EXTRA = {0x09, 0x0A, 0x0C, 0x0D}


def ranges_for(predicate):
    """The code points the predicate accepts, as a list of (lo, hi) ranges."""
    out = []
    start = None
    for cp in range(0x110000):
        if predicate(cp):
            if start is None:
                start = cp
        else:
            if start is not None:
                out.append((start, cp - 1))
                start = None
    if start is not None:
        out.append((start, 0x10FFFF))
    return out


def is_zs(cp):
    return unicodedata.category(chr(cp)) == 'Zs'


def is_punct_or_symbol(cp):
    # The category is two letters: `Po` is punctuation, `Sc` is a symbol.
    # The test is on the first letter, so it covers every sub-category.
    return unicodedata.category(chr(cp))[0] in ('P', 'S')


def hexs(v):
    return '0x%X' % v


def emit_function(name, ranges):
    """One function that answers the question for its own ranges."""
    lines = []
    for lo, hi in ranges:
        if lo == hi:
            lines.append('  if u == %s { return true }' % hexs(lo))
        else:
            lines.append('  if u >= %s && u <= %s { return true }' % (hexs(lo), hexs(hi)))
    return '\n'.join(lines)


def emit_table(kind, ranges):
    """The table for one character class, split over several functions."""
    chunks = [ranges[i:i + PER_FUNCTION] for i in range(0, len(ranges), PER_FUNCTION)]
    out = []
    out.append('///|')
    out.append('/// The ranges of the %s class, split over %d function%s so that no' %
               (kind, len(chunks), '' if len(chunks) == 1 else 's'))
    out.append('/// single one of them is large enough to overflow the native C parser.')
    out.append('///')
    for i, chunk in enumerate(chunks):
        out.append('///|')
        out.append('fn %s_%d(u : Int32) -> Bool {' % (kind, i))
        out.append(emit_function(kind, chunk))
        out.append('  false')
        out.append('}')
    out.append('///|')
    out.append('fn %s(u : Int32) -> Bool {' % kind)
    for i in range(len(chunks)):
        out.append('  if %s_%d(u) { return true }' % (kind, i))
    out.append('  false')
    out.append('}')
    return '\n'.join(out)


def main():
    ws = ranges_for(lambda cp: is_zs(cp) or cp in WHITESPACE_EXTRA)
    ps = ranges_for(is_punct_or_symbol)
    sys.stderr.write('unicode %s: %d whitespace ranges, %d punct/symbol ranges\n' %
                     (unicodedata.unidata_version, len(ws), len(ps)))

    text = []
    text.append('///|')
    text.append('/// The Unicode character classes the Markdown parser needs.')
    text.append('///')
    text.append('/// CommonMark defines a *Unicode whitespace character* as a character')
    text.append('/// in the Unicode `Zs` general category, or a tab, a line feed, a form')
    text.append('/// feed or a carriage return; and a *Unicode punctuation character* as a')
    text.append('/// character in the Unicode `P` or `S` general categories. The ASCII')
    text.append('/// helpers in src/text cannot express either, and the distinction')
    text.append('/// matters: `*£*bravo.` is not emphasis, because `£` is a symbol and')
    text.append('/// therefore punctuation for this purpose.')
    text.append('///')
    text.append('/// The tables are generated - see tools/gen_unicode_table.py.')
    text.append('')
    text.append('///|')
    text.append('/// Is the character a Unicode whitespace character?')
    text.append('///')
    text.append('pub fn is_unicode_whitespace(c : Char) -> Bool {')
    text.append('  whitespace(c.to_int())')
    text.append('}')
    text.append('')
    text.append('///|')
    text.append('/// Is the character a Unicode punctuation character (the `P` and `S`')
    text.append('/// general categories)?')
    text.append('///')
    text.append('pub fn is_unicode_punctuation(c : Char) -> Bool {')
    text.append('  punct_symbol(c.to_int())')
    text.append('}')
    text.append('')
    text.append(emit_table('whitespace', ws))
    text.append('')
    text.append(emit_table('punct_symbol', ps))
    text.append('')

    with open(OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(text))
    print('wrote %s' % os.path.relpath(OUT, ROOT))


if __name__ == '__main__':
    main()
