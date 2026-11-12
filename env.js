/**
 * Where the tools this repository needs live.
 *
 * The three scripts that drive a browser (build_pdf.js, verify_page.js,
 * verify_md_page.js) all need the same three things: the Chrome binary, the
 * mermaid runtime and puppeteer. On the machine this was written on they sat
 * in well-known places; on another machine they sit somewhere else. So each
 * one is looked up in the same order, and the lookup is written down here
 * once instead of three times:
 *
 *   1. an environment variable, if it is set
 *   2. the usual places for the platform
 *   3. whatever puppeteer itself downloaded, for the browser
 *
 * The environment variables are CHROME, MERMAID_JS and PUPPETEER_MODULE.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

/** The repository root: the directory this file sits in. */
const ROOT = path.dirname(__filename);

function exists(p) {
  try {
    return fs.existsSync(p);
  } catch {
    return false;
  }
}

/** The directories a global npm install puts its packages in. */
function npmRoots() {
  const roots = [];
  if (process.env.NPM_CONFIG_PREFIX) {
    roots.push(path.join(process.env.NPM_CONFIG_PREFIX, 'lib', 'node_modules'));
  }
  if (process.platform === 'win32') {
    if (process.env.APPDATA) roots.push(path.join(process.env.APPDATA, 'npm', 'node_modules'));
    if (process.env.ProgramData) roots.push(path.join(process.env.ProgramData, 'npm', 'node_modules'));
  } else {
    roots.push('/usr/local/lib/node_modules');
    roots.push('/usr/lib/node_modules');
    const home = os.homedir();
    if (home) {
      roots.push(path.join(home, '.npm-global', 'lib', 'node_modules'));
      roots.push(path.join(home, '.local', 'lib', 'node_modules'));
    }
  }
  return roots;
}

/**
 * puppeteer, wherever it is.
 *
 * A local install wins (npm i puppeteer), then the copy inside the global
 * mermaid-cli package, then a plain global install.
 */
function findPuppeteer() {
  const candidates = [];
  if (process.env.PUPPETEER_MODULE) candidates.push(process.env.PUPPETEER_MODULE);
  candidates.push('puppeteer');
  for (const root of npmRoots()) {
    candidates.push(path.join(root, '@mermaid-js', 'mermaid-cli', 'node_modules', 'puppeteer'));
    candidates.push(path.join(root, 'puppeteer'));
  }
  for (const c of candidates) {
    try {
      return require(c);
    } catch {
      // keep looking
    }
  }
  throw new Error(
    'puppeteer not found. Install it (npm i puppeteer), or point ' +
    'PUPPETEER_MODULE at an existing copy.',
  );
}

/**
 * The browser binary.
 *
 * An empty string means "let puppeteer decide", which is right when
 * puppeteer downloaded a browser of its own.
 */
function findChrome() {
  const wanted = process.env.CHROME || process.env.CHROME_PATH;
  if (wanted) {
    if (!exists(wanted)) throw new Error(`no browser at ${wanted}`);
    return wanted;
  }
  const fixed =
    process.platform === 'win32'
      ? [
          'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
          'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
          'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
          'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
        ]
      : process.platform === 'darwin'
        ? [
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
            '/Applications/Chromium.app/Contents/MacOS/Chromium',
            '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
          ]
        : [
            '/usr/bin/google-chrome',
            '/usr/bin/google-chrome-stable',
            '/usr/bin/chromium',
            '/usr/bin/chromium-browser',
            '/usr/bin/microsoft-edge',
          ];
  for (const c of fixed) {
    if (exists(c)) return c;
  }
  return '';
}

/**
 * The mermaid runtime, the file the page inlines.
 *
 * An empty string means "not found": the caller then has to decide what to
 * do about it, rather than silently inlining nothing.
 */
function findMermaidJs() {
  const wanted = process.env.MERMAID_JS;
  if (wanted) {
    if (!exists(wanted)) throw new Error(`no mermaid runtime at ${wanted}`);
    return wanted;
  }
  const relatives = [
    path.join('@mermaid-js', 'mermaid-cli', 'node_modules', 'mermaid', 'dist', 'mermaid.min.js'),
    path.join('mermaid', 'dist', 'mermaid.min.js'),
  ];
  for (const root of npmRoots()) {
    for (const rel of relatives) {
      const c = path.join(root, rel);
      if (exists(c)) return c;
    }
  }
  return '';
}

module.exports = { ROOT, findPuppeteer, findChrome, findMermaidJs, exists };
