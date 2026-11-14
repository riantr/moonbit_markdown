// Generate the MoonBit entity table from the reference implementation's.
//
// The HTML5 named character references are a fixed list; the reference
// CommonMark implementation carries the whole table, so the table is lifted
// from there rather than typed out by hand.
//
//   node tools/gen_entity_table.js
//
// The result is src/md/entity.mbt, which is part of the package.
//
// The table is written as a dispatcher plus a number of small functions, not
// as one function with two thousand match arms: the C parser of MSVC gives up
// on the latter (C1026, parser stack overflow), and `moon build --release` on
// Windows fails because of it. The chunks are tried in order, so the first
// definition of a name still wins and an unknown name still yields None.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TMP = path.join(__dirname, 'commonmark');
const REF = path.join(TMP, 'commonmark.js');
const URL = 'https://cdn.jsdelivr.net/npm/commonmark@0.30.0/dist/commonmark.js';

function fetchReference() {
  fs.mkdirSync(TMP, { recursive: true });
  if (fs.existsSync(REF)) return;
  const r = spawnSync('curl.exe', ['-sS', '--max-time', '120', '-o', REF, URL], { stdio: 'inherit' });
  if (r.status !== 0 || !fs.existsSync(REF)) {
    console.error('could not download ' + URL);
    process.exit(1);
  }
}

fetchReference();
const src = fs.readFileSync(REF, 'utf8');

// `var Name = "chars";` — one per entity.
const re = /^[ \t]+var ([A-Za-z][A-Za-z0-9]*) = "((?:[^"\\]|\\.)*)";\r?$/gm;
const map = new Map();
let m;
while ((m = re.exec(src)) !== null) {
  if (map.has(m[1])) continue;
  map.set(m[1], JSON.parse('"' + m[2] + '"'));
}

const names = [...map.keys()].sort();
console.log('entities found: ' + names.length);

// How many match arms one function may hold. The limit that matters here is
// the C parser's, not the MoonBit compiler's.
const CHUNK_SIZE = 64;

function escapeValue(value) {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
}

const chunks = [];
for (let i = 0; i < names.length; i += CHUNK_SIZE) {
  chunks.push(names.slice(i, i + CHUNK_SIZE));
}

// The chunks, one function each.
const chunkFns = chunks
  .map((chunk, index) => {
    const arms = chunk.map(
      (n) => '    "' + n + '" => Some("' + escapeValue(map.get(n)) + '")'
    );
    return `///|
fn entity_value_${index}(name : String) -> String? {
  match name {
${arms.join('\n')}
    _ => None
  }
}`;
  })
  .join('\n\n');

// The dispatcher: the chunks in order, the first hit wins.
const dispatch = chunks
  .slice(1)
  .map((_, index) => `  if result is None {
    result = entity_value_${index + 1}(name)
  }`)
  .join('\n');

const out = `///|
/// The HTML5 named character references.
///
/// A Markdown document may write \`&amp;\` or \`&#233;\` instead of the
/// character itself, and the browser has to show the character. The table is
/// the HTML5 list; the numeric forms are handled separately, because those
/// do not need a table at all.
///
/// The table is generated - see tools/gen_entity_table.js.

///|
fn entity_value(name : String) -> String? {
  let mut result = entity_value_0(name)
${dispatch}
  result
}

${chunkFns}
`;

fs.writeFileSync(path.join(ROOT, 'src', 'md', 'entity.mbt'), out, 'utf8');
console.log('wrote src/md/entity.mbt (' + out.length + ' bytes)');
