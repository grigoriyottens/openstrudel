import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { describe, it, expect } from 'vitest';
const catalog = JSON.parse(readFileSync('public/localizations.json', 'utf8'));
function localizer(language?: string) {
  const context = vm.createContext({});
  vm.runInContext(readFileSync('public/localization.js', 'utf8'), context);
  return context.StrudelLocale.create(catalog, language);
}
describe('interface languages', () => {
  it('uses English by default and preserves user text inside placeholders', () => {
    const l = localizer();
    expect(l.language).toBe('en');
    expect(l.text('Удалить «{0}»?', ['Личное {1}'])).toBe('Delete “Личное {1}”?');
    expect(l.text('Удалить «{0}»?', ['<script>'])).toBe('Delete “<script>”?');
  });
  it('supports Hebrew without letting an address reorder the surrounding sentence', () => {
    const l = localizer('he');
    expect(l.direction).toBe('rtl');
    expect(l.text('Connection {0}', ['me@example.com'])).toContain('\u2068me@example.com\u2069');
    l.setLanguage('unknown');
    expect(l.language).toBe('en');
  });
  it('has five complete translations with matching placeholders', () => {
    for (const [key, entries] of Object.entries(catalog) as [string, Record<string,string>][]) {
      const slots = (key.match(/\{\d+\}/g) || []).sort();
      for (const language of ['en','ru','fr','es','he']) {
        expect(entries[language], `${language}: ${key}`).toBeTruthy();
        expect((entries[language].match(/\{\d+\}/g) || []).sort(), `${language}: ${key}`).toEqual(slots);
        expect(entries[language], `${language}: ${key}`).not.toMatch(/\bAI\b/);
      }
    }
  });
  it('localizes server errors, keeping interpolated values intact', () => {
    const l = localizer();
    expect(l.error('Удалить «Работа {1}»?')).toBe('Delete “Работа {1}”?');
    expect(l.error('Обновите OpenStrudel на устройстве сотрудника, чтобы выбирать модель.')).toBe('Update OpenStrudel on this assistant’s device to choose a model.');
    // Renaming a device or an employee can return these.
    for (const error of ['Введите название до 120 символов.', 'Сотрудник не найден.', 'Сотрудник не найден', 'Сотрудник удалён.', 'Сотрудник с таким именем уже есть',
      'Проверьте имя и длину характера', 'Сотрудник переносится. Новое поручение можно отправить после завершения.',
      // An owner's device and a colleague's link get these.
      'Ссылка устарела или уже использована. Попросите новую.', 'Это устройство отключено. Подключитесь заново по новой ссылке.',
      // Subscriptions: Grok's sign-in on its device, its owner-only turns and its limits.
      'Войдите в Grok снова в настройках аккаунтов.', 'Подписка Grok работает только в чатах владельца. Для коллег и групп выберите модель xAI с ключом API.',
      'Лимит подписки Grok исчерпан. Повторите позже или выберите другую модель.', 'Grok не отвечает. Повторите вход позже.', 'Вход в Grok не завершён: Error: access_denied',
      'Код входа в Grok истёк. Начните вход снова.', 'Устройство не на связи. Войдите в подписку, когда оно подключится.', 'Kimi Code не принял ключ. Замените его в настройках аккаунтов.']) {
      expect(l.error(error), error).not.toBe(l.text('Не удалось получить ответ. Попробуйте ещё раз.'));
    }
  });
  it('explains every refusal of a move between devices instead of claiming no reply came', () => {
    const l = localizer(), lost = l.text('Не удалось получить ответ. Попробуйте ещё раз.');
    const steps = readFileSync('src/agent-move.ts', 'utf8').split('/** Durable control state')[0]!;
    const errors = [...steps.matchAll(/HomeError\("([^"]+)"/g)].map(m => m[1]!);
    expect(errors.length).toBeGreaterThan(20);
    errors.push('Сотрудники ещё работают. Дождитесь завершения их ответов и повторите экспорт.', 'Переносить сотрудников может владелец устройства.',
      'Подключённое устройство изменилось. Проверьте подключение перед переносом.', 'Выберите сотрудника для переноса.');
    for (const error of errors) expect(l.error(error), error).not.toBe(lost);
  });
});
