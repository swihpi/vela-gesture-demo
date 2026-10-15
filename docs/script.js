const buttons = document.querySelectorAll('[data-gesture]');
for (const button of buttons) {
  button.addEventListener('click', () => {
    for (const other of buttons) {
      other.classList.toggle('chosen', other === button);
      other.setAttribute('aria-pressed', String(other === button));
    }
    document.getElementById('demo-hand').textContent = button.dataset.glyph;
    document.getElementById('demo-name').textContent = button.dataset.gesture;
    document.getElementById('demo-action').textContent = button.dataset.action;
  });
}
