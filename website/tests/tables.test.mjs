import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Window } from 'happy-dom';

test('Markdown tables retain headers, cells and inline code inside keyboard-accessible scroll cards', async () => {
  const window = new Window();
  window.document.write(await readFile(new URL('../dist/docs/quick-add-shortcuts/index.html', import.meta.url), 'utf8'));
  const tables = [...window.document.querySelectorAll('.sl-markdown-content table')];
  assert.ok(tables.length > 0);
  for (const table of tables) {
    const card = table.parentElement;
    assert.ok(card.classList.contains('viku-table-card'));
    assert.equal(card.tabIndex, 0);
    assert.equal(card.getAttribute('role'), 'region');
    assert.ok(card.getAttribute('aria-label'));
    assert.equal(card.querySelectorAll('table').length, 1);
    assert.ok(table.querySelector('thead th'));
    assert.ok(table.querySelector('tbody td'));
  }
  assert.equal(tables[0].querySelectorAll('thead th').length, 4);
  assert.equal(tables[0].querySelector('tbody td').textContent, 'Project');
  assert.ok(tables[0].querySelector('tbody code'));
  await window.happyDOM.abort();
});
