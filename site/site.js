const appearance = document.querySelector('#appearance');
function setAppearance(value) {
  if (value === 'auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = value;
  try { localStorage.setItem('notchcompressor-appearance', value); } catch {}
}
try { const saved = localStorage.getItem('notchcompressor-appearance'); if (['auto', 'light', 'dark'].includes(saved)) appearance.value = saved; } catch {}
setAppearance(appearance.value);
appearance.addEventListener('change', () => setAppearance(appearance.value));
const sample = document.querySelector('.sample');
const notch = document.querySelector('.notch');
const zones = document.querySelector('.zones');
const result = document.querySelector('.demo-result');
sample.addEventListener('click', () => {
  const expanded = sample.getAttribute('aria-expanded') !== 'true';
  sample.setAttribute('aria-expanded', String(expanded));
  notch.classList.toggle('open', expanded);
  zones.hidden = !expanded;
  result.textContent = expanded ? result.dataset.open : result.dataset.closed;
});
zones.querySelectorAll('button').forEach(button => {
  button.addEventListener('click', () => {
    zones.querySelectorAll('button').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    result.textContent = button.dataset.description;
  });
});
