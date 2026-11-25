const appearance = document.querySelector('#appearance');
const value = document.querySelector('.appearance-value');
appearance.value = document.documentElement.dataset.theme || 'auto';
function updateAppearance() {
  if (appearance.value === 'auto') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = appearance.value;
  value.textContent = appearance.selectedOptions[0].textContent;
  value.hidden = false;
}
appearance.addEventListener('change', () => {
  try { localStorage.setItem('notchcompressor-appearance', appearance.value); } catch {}
  updateAppearance();
});
updateAppearance();

document.addEventListener('notchcompressor-language', updateAppearance);
