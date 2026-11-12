// Check that a Markdown page with a Mermaid diagram really renders it.
const path = require('path');
const { findPuppeteer, findChrome } = require('./env');

const puppeteer = findPuppeteer();
const CHROME = findChrome();

(async () => {
  const file = process.argv[2];
  const browser = await puppeteer.launch({
    // an empty path means "the browser puppeteer brought with it"
    ...(CHROME ? { executablePath: CHROME } : {}),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    headless: 'new',
    protocolTimeout: 600000,
  });
  const page = await browser.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto('file:///' + path.resolve(file).replace(/\\/g, '/'), { waitUntil: 'networkidle0' });
  await new Promise((r) => setTimeout(r, 3000));
  const r = await page.evaluate(() => {
    const m = document.querySelector('div.mermaid');
    return {
      hasBlock: !!m,
      svg: m ? m.querySelectorAll('svg').length : 0,
      nodes: m ? m.querySelectorAll('g.node').length : 0,
      h1: document.querySelectorAll('h1').length,
      h2: document.querySelectorAll('h2').length,
      table: document.querySelectorAll('table').length,
      li: document.querySelectorAll('li').length,
      text: (document.body.innerText || '').slice(0, 80),
    };
  });
  console.log(JSON.stringify(r, null, 2));
  console.log('console errors:', errors.length, errors.slice(0, 3));
  const ok = r.svg > 0 && r.nodes > 0 && r.h1 === 1 && r.table === 1 && errors.length === 0;
  console.log(ok ? 'MD PAGE CHECKS PASSED' : 'MD PAGE CHECKS FAILED');
  await browser.close();
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error('HARNESS ERROR', e); process.exit(1); });
