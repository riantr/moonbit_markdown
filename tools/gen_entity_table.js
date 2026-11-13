// Generate the MoonBit entity table from the reference implementation's.
//
// The HTML5 named character references are a fixed list; the reference
// CommonMark implementation carries the whole table, so the table is lifted
// from there rather than typed out by hand.
//
//   node tools/gen_entity_table.js
//
// The result is src/md/entity.mbt, which is part of the package.
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

const body = names.map((n) => {
  const esc = map
    .get(n)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
  return '  "' + n + '" => Some("' + esc + '")';
});

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
  match name {
${body.join('\n')}
    _ => None
  }
}
`;

fs.writeFileSync(path.join(ROOT, 'src', 'md', 'entity.mbt'), out, 'utf8');
console.log('wrote src/md/entity.mbt (' + out.length + ' bytes)');
