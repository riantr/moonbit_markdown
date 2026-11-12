/**
 * Verify a generated HTML5 page in a real browser.
 *
 * Checks, in Chrome, on the page the MoonBit tool produced:
 *   - the page loads without a console error
 *   - the overview renders and has one node per file plus the scan node
 *   - the sidebar lists every file
 *   - every NOTICE state of the scan appears in the sidebar
 *   - clicking a file renders that file's sub-diagram
 *
 * Usage: node verify_page.js <page.html> <scan.mmd>
 */
const fs = require('fs');
const path = require('path');
const puppeteer = require('C:/Users/hp/AppData/Roaming/npm/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PAGE = process.argv[2];
const SCAN = process.argv[3];

const EM = String.fromCharCode(8212);

function scanGroundTruth(src) {
  const lines = src.split(/\r?\n/);
  const files = [];
  let cur = null;
  for (const L of lines) {
    const m = /^ {4}scan --> (f\d+) :/.exec(L);
    if (m) { cur = { id: m[1], notices: [] }; files.push(cur); continue; }
    if (!cur) continue;
    const s = /^\s+state "(.*?)" as ([A-Za-z0-9_]+)\s*$/.exec(L);
    if (s && s[1].indexOf('NOTICE ' + EM + ' ') === 0) cur.notices.push(s[2]);
  }
  return files;
}

(async () => {
  const failures = [];
  const check = (name, cond, detail = '') => {
    console.log(`[${cond ? 'PASS' : 'FAIL'}] ${name}${detail ? '  -> ' + detail : ''}`);
    if (!cond) failures.push(name);
  };

  const truth = scanGroundTruth(fs.readFileSync(SCAN, 'utf8'));
  const totalNotices = truth.reduce((a, f) => a + f.notices.length, 0);
  console.log(`source: ${truth.length} files, ${totalNotices} notice states`);

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    headless: 'new',
    protocolTimeout: 900000,
  });
  const page = await browser.newPage();
  await page.setDefaultTimeout(900000);
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.goto('file:///' + path.resolve(PAGE).replace(/\\/g, '/'), { waitUntil: 'load' });
  // wait for the overview to be drawn
  await page.waitForFunction(() => {
    const v = document.getElementById('viewport');
    return v && v.querySelector('svg');
  }, { timeout: 600000 });

  const overview = await page.evaluate(() => {
    const svg = document.querySelector('#viewport svg');
    const nodes = svg ? svg.querySelectorAll('g.node') : [];
    const vb = svg ? (svg.getAttribute('viewBox') || '').split(' ') : [];
    return {
      nodes: nodes.length,
      w: Number(vb[2]) || 0,
      h: Number(vb[3]) || 0,
      fileItems: document.querySelectorAll('.fitem').length,
      stats: (document.getElementById('stats') || {}).textContent || '',
      counts: JSON.parse(document.getElementById('counts').textContent),
      files: JSON.parse(document.getElementById('files').textContent),
    };
  });

  console.log(`overview: ${overview.nodes} nodes, ${Math.round(overview.w)}x${Math.round(overview.h)} px`);
  console.log(`stats: ${overview.stats.replace(/\s+/g, ' ').trim()}`);
  check('the page loads without a console error', errors.length === 0, errors.slice(0, 3).join(' | '));
  check('the overview draws one node per file plus scan',
    overview.nodes === truth.length + 1, `${overview.nodes} nodes for ${truth.length} files`);
  check('the sidebar lists every file', overview.fileItems === truth.length, `${overview.fileItems} items`);
  check('the page reports the drawn notice count',
    overview.counts.drawnNotices === totalNotices, `${overview.counts.drawnNotices} vs ${totalNotices}`);
  check('the page reports the drawn finding count',
    overview.counts.drawnFindings === 1, String(overview.counts.drawnFindings));
  check('the data carries every file', overview.files.length === truth.length);

  // click the file with a finding and check its sub-diagram renders
  const withFinding = truth.find((f) => f.id === 'f98');
  if (withFinding) {
    await page.evaluate((id) => {
      const row = document.querySelector('.fitem[data-id="' + id + '"]');
      if (row) row.click();
    }, 'f98');
    await page.waitForFunction(() => {
      const v = document.getElementById('viewport');
      const svg = v && v.querySelector('svg');
      return svg && svg.querySelectorAll('g.node').length > 5;
    }, { timeout: 600000 });
    const detail = await page.evaluate(() => {
      const svg = document.querySelector('#viewport svg');
      return {
        nodes: svg.querySelectorAll('g.node').length,
        hasFinding: (svg.textContent || '').indexOf('OperatorMismatch') >= 0,
        panel: (document.getElementById('noticepanel') || {}).textContent || '',
      };
    });
    check('the clicked file renders its own diagram', detail.nodes > 5, `${detail.nodes} nodes`);
    check('the sub-diagram shows the finding', detail.hasFinding);
    check('the findings panel is filled', detail.panel.indexOf('OperatorMismatch') >= 0);
  }

  await page.screenshot({ path: path.join(path.dirname(PAGE), 'moonbit_page.png'), fullPage: false });
  await browser.close();

  console.log();
  if (failures.length) {
    console.log('FAILURES:\n  ' + failures.join('\n  '));
    process.exit(1);
  }
  console.log('ALL PAGE CHECKS PASSED');
})().catch((e) => { console.error('ERR', e); process.exit(1); });
