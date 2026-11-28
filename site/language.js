// Japanese is the no-script fallback. Translate existing nodes without replacing
// controls, so focus, event listeners and the running demo survive language changes.
(() => {
  const fields = JSON.parse(document.querySelector('#english-copy').textContent).map(field => {
    const element = document.querySelector(`[data-i18n="${field.id}"]`);
    return {
      element,
      texts: field.texts.map(([index, en]) => ({ node: element.childNodes[index], en, ja: element.childNodes[index].nodeValue })),
      attributes: Object.entries(field.attributes).map(([name, en]) => ({ name, en, ja: element.getAttribute(name) }))
    };
  });
  const button = document.querySelector('button.language');
  const valid = value => value === 'ja' || value === 'en';
  const browserLanguage = () => (navigator.languages?.length ? navigator.languages : [navigator.language])
    .map(tag => tag.split('-')[0].toLowerCase()).find(valid) || 'en';
  let choice;
  try { choice = localStorage.getItem('notchcompressor-language'); } catch {}
  const url = new URL(location.href);
  const requested = url.searchParams.get('lang');
  function remember(language) {
    choice = language;
    try { localStorage.setItem('notchcompressor-language', language); } catch {}
  }
  function display(language) {
    document.documentElement.lang = language;
    for (const field of fields) {
      for (const text of field.texts) text.node.nodeValue = text[language];
      for (const attribute of field.attributes) field.element.setAttribute(attribute.name, attribute[language]);
    }
    for (const field of ['title', 'description']) {
      const value = document.querySelector(`meta[property="og:${field}"]`)?.content;
      const target = document.querySelector(`meta[name="twitter:${field}"]`);
      if (target && value) target.content = value;
    }
    document.querySelector('meta[property="og:locale"]')?.setAttribute('content', language === 'ja' ? 'ja_JP' : 'en_US');
    document.querySelector('meta[property="og:locale:alternate"]')?.setAttribute('content', language === 'ja' ? 'en_US' : 'ja_JP');
    button.lang = language === 'ja' ? 'en' : 'ja';
    button.textContent = language === 'ja' ? 'English' : '日本語';
    button.hidden = false;
    document.dispatchEvent(new Event('notchcompressor-language'));
  }
  if (valid(requested)) {
    remember(requested);
    url.searchParams.delete('lang');
    history.replaceState(history.state, '', url);
  }
  display(valid(choice) ? choice : browserLanguage());
  button.addEventListener('click', () => { remember(button.lang); display(choice); });
  addEventListener('languagechange', () => { if (!valid(choice)) display(browserLanguage()); });
})();
