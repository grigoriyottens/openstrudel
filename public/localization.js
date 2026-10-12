/* One catalogue shared with the native app. Only application copy is translated. */
(function(root) {
  const languages = [['en','English'],['ru','Русский'],['fr','Français'],['es','Español'],['he','עברית']];
  function create(catalog, initial) {
    let language = 'en';
    const valid = value => languages.some(([code]) => code === value) ? value : 'en';
    const locale = {
      get language() { return language; },
      get direction() { return language === 'he' ? 'rtl' : 'ltr'; },
      setLanguage(value) { language = valid(value); },
      text(key, args = []) {
        const template = catalog[key]?.[language] ?? catalog[key]?.en ?? key;
        return template.replace(/\{(\d+)\}/g, (slot, index) => {
          if (index >= args.length) return slot;
          const value = String(args[index]);
          return language === 'he' ? '\u2068' + value + '\u2069' : value;
        });
      },
      error(message) {
        if (catalog[message]) return locale.text(message);
        // Errors are service copy. Conversation bodies and employee names never
        // pass through this path, even if they happen to match a catalogue key.
        for (const [key] of Object.entries(catalog)) {
          if (!key.includes('{0}') || key.includes('<')) continue;
          const pattern = key.split(/(\{\d+\})/).map(part => /^\{\d+\}$/.test(part) ? '([\\s\\S]*?)' : part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('');
          const match = new RegExp('^' + pattern + '$').exec(message);
          if (match) return locale.text(key, match.slice(1));
        }
        return /[а-яё]/i.test(message) && language !== 'ru' ? locale.text('Не удалось получить ответ. Попробуйте ещё раз.') : message;
      }
    };
    locale.setLanguage(initial);
    return locale;
  }
  root.StrudelLocale = {create, languages};
  if (typeof document === 'undefined') return;
  let saved;
  try { saved = localStorage.getItem('openstrudel.language'); } catch {}
  root.i18n = create({}, saved);
  root.t = (key, ...args) => root.i18n.text(key, args);
  root.applyInterfaceLanguage = () => {
    document.documentElement.lang = root.i18n.language;
    document.documentElement.dir = root.i18n.direction;
    for (const node of document.querySelectorAll('[data-i18n]')) node.textContent = t(node.dataset.i18n);
    for (const attribute of ['title','placeholder','aria-label']) {
      for (const node of document.querySelectorAll('[data-i18n-' + attribute + ']')) node.setAttribute(attribute, t(node.getAttribute('data-i18n-' + attribute)));
    }
  };
  root.setInterfaceLanguage = language => {
    root.i18n.setLanguage(language);
    try { localStorage.setItem('openstrudel.language', root.i18n.language); } catch {}
    root.applyInterfaceLanguage();
  };
  const catalogueURL = new URL('localizations.json', document.currentScript?.src || document.baseURI);
  root.languageReady = fetch(catalogueURL, {credentials:'same-origin'}).then(async response => {
    if (!response.ok) throw new Error('Language resources could not load.');
    root.i18n = create(await response.json(), saved);
    root.applyInterfaceLanguage();
  });
})(globalThis);
