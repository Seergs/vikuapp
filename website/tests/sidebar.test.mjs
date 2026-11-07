import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { Window } from 'happy-dom';

const dist = new URL('../dist/', import.meta.url);
const routes = ['docs', ...['offline-mode', 'push-notifications', 'quick-add-shortcuts', 'server-version-support'].map(slug => `docs/${slug}`)];

test('docs sidebar preserves real links and selects only the current page on every route', async () => {
  for (const route of routes) {
    const window = new Window();
    window.document.write(await readFile(new URL(`${route}/index.html`, dist), 'utf8'));
    const sidebar = window.document.querySelector('.viku-docs-sidebar');
    assert.ok(sidebar, route);
    const links = [...sidebar.querySelectorAll('a[data-viku-icon]')];
    assert.equal(links.length, routes.length, route);
    for (const link of links) {
      await access(new URL(`${link.getAttribute('href').replace(/^\//, '')}index.html`, dist));
      assert.ok(link.textContent.trim(), 'Links keep accessible text labels');
    }
    const current = sidebar.querySelectorAll('a[aria-current="page"]');
    assert.equal(current.length, 1, route);
    assert.equal(current[0].getAttribute('href'), `/${route}/`);
    assert.ok(sidebar.querySelector('details[open]') || route === 'docs', 'The current guide group is expanded');
    window.happyDOM.abort();
  }
});

test('custom sidebar retains Starlight mobile navigation, preferences and state persistence', async () => {
  const window = new Window();
  window.document.write(await readFile(new URL('docs/index.html', dist), 'utf8'));
  const { document } = window;
  const pane = document.querySelector('sl-sidebar-pane#starlight__sidebar[popover]');
  assert.ok(pane);
  assert.ok(document.querySelector('[popovertarget="starlight__sidebar"]'));
  assert.ok(pane.querySelector('.viku-docs-sidebar sl-sidebar-state-persist'));
  assert.ok(pane.querySelector('starlight-theme-select select'));
  assert.ok(pane.querySelector('details > summary'));
  window.happyDOM.abort();
});
