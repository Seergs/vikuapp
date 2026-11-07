import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { Window } from 'happy-dom';
import sharp from 'sharp';
import { initializeProjectDemo } from '../src/components/landing/project-demo.ts';

const dist = new URL('../dist/', import.meta.url);
const html = await readFile(new URL('index.html', dist), 'utf8');
function page() {
  const window = new Window({ url: 'https://viku.dev' });
  window.document.write(html);
  return window;
}

test('landing offers the beta and keeps screenshots explicitly pending', () => {
  const { document } = page();
  assert.equal(document.documentElement.lang, 'en');
  assert.equal(document.querySelectorAll('h1').length, 1);
  const betaLinks = [...document.querySelectorAll('a')].filter(a => a.textContent.includes('beta'));
  assert.equal(betaLinks.length, 3);
  betaLinks.forEach(a => assert.equal(a.href, 'https://testflight.apple.com/join/aby3Bh4d'));
  assert.ok(document.querySelector('[aria-label="App screenshot coming soon"]'));
  assert.match(document.body.textContent, /iOS 26\.2/);
  assert.doesNotMatch(html, /support\.js|todo-app-scene|<x-dc|<sc-if/);
});

test('all internal landing links resolve to built pages or anchors', async () => {
  const { document } = page();
  for (const link of document.querySelectorAll('a[href]')) {
    const href = link.getAttribute('href');
    if (href.startsWith('#')) assert.ok(document.getElementById(href.slice(1)), href);
    else if (href.startsWith('/')) await access(new URL(`${href.slice(1)}index.html`, dist));
  }
  const privacy = await readFile(new URL('privacy/index.html', dist), 'utf8');
  assert.match(privacy, /full website privacy policy is being prepared/);
});

test('the default list is available without JavaScript', () => {
  const { document } = page();
  assert.equal(document.querySelector('#demo-list').hidden, false);
  assert.equal(document.querySelectorAll('#demo-list input').length, 5);
  assert.equal(document.querySelector('.view-switch').hidden, true);
  assert.equal(document.querySelector('.theme-picker').hidden, true);
});

test('switching views preserves completion and supports switching back', () => {
  const window = page();
  const { document } = window;
  initializeProjectDemo(document.querySelector('[data-project-demo]'));
  const list = document.querySelector('#demo-list');
  const board = document.querySelector('#demo-board');
  assert.equal(document.querySelector('.view-switch').hidden, false);
  const checkbox = list.querySelector('[data-task="navigation"]');
  checkbox.click();
  assert.equal(document.querySelector('[data-pending-count]').textContent, '3 remaining');
  document.querySelector('[data-view="board"]').click();
  assert.equal(list.hidden, true);
  assert.equal(board.hidden, false);
  assert.equal(document.querySelector('[data-view="board"]').getAttribute('aria-pressed'), 'true');
  const boardCheckbox = board.querySelector('[data-task="navigation"]');
  assert.equal(boardCheckbox.checked, true);
  boardCheckbox.click();
  assert.equal(checkbox.checked, false);
  assert.equal(document.querySelector('[data-pending-count]').textContent, '4 remaining');
  document.querySelector('[data-view="list"]').click();
  assert.equal(list.hidden, false);
  assert.equal(board.hidden, true);
  assert.equal(document.querySelector('[data-view="list"]').getAttribute('aria-pressed'), 'true');
});

test('completion count handles all done and restoring a task', () => {
  const { document } = page();
  initializeProjectDemo(document.querySelector('[data-project-demo]'));
  document.querySelectorAll('#demo-list input:not(:checked)').forEach(input => input.click());
  assert.equal(document.querySelector('[data-pending-count]').textContent, '0 remaining');
  document.querySelector('#demo-board input').click();
  assert.equal(document.querySelector('[data-pending-count]').textContent, '1 remaining');
});

test('initial theme respects the docs preference and blocked storage is recoverable', () => {
  const window = page();
  const script = window.document.querySelector('head script:not([src])').textContent;
  window.localStorage.setItem('starlight-theme', 'dark');
  window.eval(script);
  assert.equal(window.document.documentElement.dataset.theme, 'dark');
  window.localStorage.setItem('starlight-theme', 'light');
  window.eval(script);
  assert.equal(window.document.documentElement.dataset.theme, 'light');
  window.document.documentElement.removeAttribute('data-theme');
  Object.defineProperty(window, 'localStorage', { get() { throw new Error('Storage blocked'); } });
  assert.doesNotThrow(() => window.eval(script));
});

test('docs pages and search are still generated with the shared theme adapter', async () => {
  const docs = await readFile(new URL('docs/index.html', dist), 'utf8');
  const window = new Window();
  window.document.write(docs);
  const cssPaths = [...window.document.querySelectorAll('link[rel="stylesheet"]')].map(link => link.getAttribute('href'));
  const css = (await Promise.all(cssPaths.map(path => readFile(new URL(path.slice(1), dist), 'utf8')))).join('\n');
  assert.match(css, /--sl-color-bg:var\(--viku-color-bg\)/);
  assert.match(css, /--sl-font:var\(--viku-font-sans\)/);
  for (const slug of ['offline-mode', 'push-notifications', 'quick-add-shortcuts', 'server-version-support']) {
    await access(new URL(`docs/${slug}/index.html`, dist));
  }
  await access(new URL('pagefind/pagefind.js', dist));
});


test('icons provide real Retina images without upscaling their source', async () => {
  const { document } = page();
  for (const image of document.querySelectorAll('img.app-icon')) {
    const candidates = image.getAttribute('srcset').split(',').map(candidate => {
      const [path, width] = candidate.trim().split(/\s+/);
      return { path, width: Number.parseInt(width, 10) };
    });
    assert.ok(Math.max(...candidates.map(candidate => candidate.width)) >= Math.min(image.width * 2, 256));
    for (const candidate of candidates) {
      assert.ok(candidate.width <= 256);
      const bytes = await readFile(new URL(candidate.path.slice(1), dist));
      const metadata = await sharp(bytes).metadata();
      assert.equal(metadata.width, candidate.width);
      assert.equal(metadata.height, candidate.width);
    }
  }
});


test('priority remains visible when completing and reopening tasks in either view', async () => {
  const window = page();
  const { document } = window;
  const style = document.createElement('style');
  const sheets = [...document.querySelectorAll('link[rel="stylesheet"]')];
  style.textContent = (await Promise.all(sheets.map(sheet =>
    readFile(new URL(sheet.getAttribute('href').slice(1), dist), 'utf8')
  ))).join('\n');
  document.head.append(style);
  initializeProjectDemo(document.querySelector('[data-project-demo]'));
  const listTask = document.querySelector('#demo-list [data-task="navigation"]');
  const listDot = listTask.closest('label').querySelector('[aria-label="urgent priority"]');
  assert.equal(window.getComputedStyle(listDot).visibility || 'visible', 'visible');
  listTask.click();
  assert.equal(window.getComputedStyle(listDot).visibility || 'visible', 'visible');
  document.querySelector('[data-view="board"]').click();
  const boardTask = document.querySelector('#demo-board [data-task="navigation"]');
  const boardDot = boardTask.closest('label').querySelector('[aria-label="urgent priority"]');
  assert.equal(boardTask.checked, true);
  assert.equal(window.getComputedStyle(boardDot).visibility || 'visible', 'visible');
  boardTask.click();
  assert.equal(window.getComputedStyle(boardDot).visibility || 'visible', 'visible');
  document.querySelector('[data-view="list"]').click();
  assert.equal(listTask.checked, false);
  assert.equal(window.getComputedStyle(listDot).visibility || 'visible', 'visible');
});
