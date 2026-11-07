/** Local presentation only. No server calls or persistence. */
export function initializeProjectDemo(root: HTMLElement) {
  const controls = root.querySelector<HTMLElement>('.view-switch');
  const views = root.querySelectorAll<HTMLButtonElement>('[data-view]');
  const list = root.querySelector<HTMLElement>('#demo-list');
  const board = root.querySelector<HTMLElement>('#demo-board');
  if (!controls || !list || !board) return;
  controls.hidden = false;
  views.forEach(button => button.addEventListener('click', () => {
    const showBoard = button.dataset.view === 'board';
    list.hidden = showBoard;
    board.hidden = !showBoard;
    views.forEach(view => view.setAttribute('aria-pressed', String(view === button)));
  }));
  const checkboxes = root.querySelectorAll<HTMLInputElement>('input[data-task]');
  checkboxes.forEach(input => input.addEventListener('change', () => {
    checkboxes.forEach(peer => {
      if (peer.dataset.task === input.dataset.task) peer.checked = input.checked;
    });
    const remaining = list.querySelectorAll('input:not(:checked)').length;
    const count = root.querySelector('[data-pending-count]');
    if (count) count.textContent = `${remaining} remaining`;
  }));
}
