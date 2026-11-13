/**
 * Measure the Markdown parser against the CommonMark spec.
 *
 * The spec's 652 examples are rendered with this module's own command line
 * tool and compared with the HTML the spec expects. The two are not meant to
 * be byte-identical - the renderer adds heading ids and language classes,
 * the spec writes entities as characters - so both sides are reduced to the
 * same canonical form before they are compared.
 *
 *   node tools/commonmark_spec.js            # run and report
 *   node tools/commonmark_spec.js --show Links 5   # show the failures of a section
 *
 * The spec is downloaded on the first run and kept next to this script.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const WORK = path.join(__dirname, 'commonmark');
const SPEC_URL = 'https://spec.commonmark.org/0.31.2/spec.json';
const SPEC_FILE = path.join(WORK, 'spec.json');
const IN_DIR = path.join(WORK, 'in');
const OUT_DIR = path.join(WORK, 'out');

/** The HTML5 named character references, as the spec knows them. */
const ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0',
  copy: '\u00a9', AElig: '\u00c6', Dcaron: '\u010e', frac34: '\u00be',
  HilbertSpace: '\u210b', DifferentialD: '\u2146',
  ClockwiseContourIntegral: '\u2232', ngE: '\u2267\u0338',
};

function decodeEntities(s) {
  return s.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g, (m, name) => {
    if (name[0] === '#') {
      const code = name[1] === 'x' || name[1] === 'X'
        ? parseInt(name.slice(2), 16)
        : parseInt(name.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    const hit = ENTITIES[name];
    return hit === undefined ? m : hit;
  });
}

/** The body of a rendered page: what the renderer produced. */
function bodyOf(html) {
  const m = /<main>([\s\S]*)<\/main>/.exec(html);
  return m ? m[1] : html;
}

/**
 * Reduce HTML to a canonical token stream.
 *
 * The whitespace between two tags carries no meaning: the spec writes
 * `<ul>\n<li>` where the renderer writes `<ul><li>`, and the two are the same
 * document. The attributes that matter are kept, the ones that do not are
 * dropped.
 */
function canonical(html) {
  let out = '';
  const re = /<\/?([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    if (m[3] !== undefined) {
      if (/^\s*$/.test(m[3])) continue;
      out += decodeEntities(m[3]).replace(/\s+/g, ' ');
      continue;
    }
    const tag = m[1].toLowerCase();
    if (m[0].startsWith('</')) {
      out += '</' + tag + '>';
      continue;
    }
    const attrs = m[2] || '';
    const kept = [];
    for (const name of ['href', 'src', 'alt']) {
      const a = new RegExp('\\b' + name + '\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', 'i').exec(attrs);
      if (a) {
        const v = a[2] !== undefined ? a[2] : a[3] !== undefined ? a[3] : a[4];
        kept.push(name + '=' + decodeEntities(v));
      }
    }
    out += '<' + tag + (kept.length ? ' ' + kept.join(' ') : '') + '>';
  }
  return out.replace(/\s+/g, ' ').trim();
}

function ensureSpec() {
  fs.mkdirSync(WORK, { recursive: true });
  if (fs.existsSync(SPEC_FILE)) return;
  console.log('downloading the spec ...');
  const r = spawnSync('curl.exe', ['-sS', '--max-time', '120', '-o', SPEC_FILE, SPEC_URL], {
    stdio: 'inherit',
  });
  if (r.status !== 0 || !fs.existsSync(SPEC_FILE)) {
    console.error('could not download ' + SPEC_URL);
    process.exit(1);
  }
}

function prepare(spec) {
  fs.rmSync(IN_DIR, { recursive: true, force: true });
  fs.mkdirSync(IN_DIR, { recursive: true });
  fs.mkdirSync(OUT_DIR, { recursive: true });
  spec.forEach((e, i) => {
    fs.writeFileSync(path.join(IN_DIR, String(i + 1).padStart(4, '0') + '.md'), e.markdown, 'utf8');
  });
}

function renderAll(spec) {
  const t0 = Date.now();
  let failed = 0;
  spec.forEach((e, i) => {
    const name = String(i + 1).padStart(4, '0');
    const r = spawnSync('moon', ['run', '.', 'md2html', path.join(IN_DIR, name + '.md'), path.join(OUT_DIR, name + '.html')], {
      cwd: ROOT,
      stdio: 'ignore',
      shell: process.platform === 'win32',
    });
    if (r.status !== 0) {
      failed += 1;
      console.error('example ' + e.example + ' did not render');
    }
  });
  console.log('rendered ' + spec.length + ' examples in ' + ((Date.now() - t0) / 1000).toFixed(1) +
    ' s, ' + failed + ' failed');
}

function compare(spec) {
  const results = [];
  for (let i = 0; i < spec.length; i += 1) {
    const e = spec[i];
    const p = path.join(OUT_DIR, String(i + 1).padStart(4, '0') + '.html');
    let mine = '';
    try {
      mine = fs.readFileSync(p, 'utf8');
    } catch {
      results.push({ n: e.example, section: e.section, ok: false, why: 'no output' });
      continue;
    }
    const a = canonical(bodyOf(mine));
    const b = canonical(e.html);
    results.push({
      n: e.example, section: e.section, ok: a === b,
      mine: a, want: b, markdown: e.markdown,
    });
  }
  return results;
}

function report(results) {
  const pass = results.filter((r) => r.ok).length;
  console.log('');
  console.log('CommonMark 0.31.2 conformance: ' + pass + '/' + results.length +
    ' (' + ((pass / results.length) * 100).toFixed(1) + '%)');
  console.log('');
  const bySection = new Map();
  for (const r of results) {
    const s = bySection.get(r.section) || { pass: 0, total: 0 };
    s.total += 1;
    if (r.ok) s.pass += 1;
    bySection.set(r.section, s);
  }
  for (const [name, s] of bySection) {
    const pct = ((s.pass / s.total) * 100).toFixed(0);
    console.log('  ' + name.padEnd(42) + s.pass + '/' + s.total + '  (' + pct + '%)' +
      (s.pass === s.total ? '' : '   <-- ' + (s.total - s.pass) + ' differ'));
  }
  return pass;
}

function show(results, section, limit) {
  let shown = 0;
  for (const r of results) {
    if (r.ok) continue;
    if (section !== 'all' && r.section !== section) continue;
    shown += 1;
    if (shown > limit) break;
    console.log('#### example ' + r.n + ' [' + r.section + ']');
    console.log('--- markdown ---\n' + JSON.stringify(r.markdown));
    console.log('--- expected ---\n' + r.want);
    console.log('--- mine ---\n' + r.mine);
    console.log('');
  }
}

function main() {
  const args = process.argv.slice(2);
  ensureSpec();
  const spec = JSON.parse(fs.readFileSync(SPEC_FILE, 'utf8'));
  if (args[0] === '--show') {
    // compare what is already rendered, without rendering again
    const results = compare(spec);
    show(results, args[1] || 'all', Number(args[2] || 5));
    return;
  }
  prepare(spec);
  renderAll(spec);
  const results = compare(spec);
  report(results);
  fs.writeFileSync(path.join(WORK, 'result.json'), JSON.stringify(results, null, 1));
}

main();
