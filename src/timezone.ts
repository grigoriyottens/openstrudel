import type { Store } from './store.js';
import { HomeError } from './home.js';

const key = 'owner.timezone';
export function ownerTimezone(store: Store): string {
  return store.getSetting(key) ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
}
export function saveOwnerTimezone(store: Store, value: unknown, initialize = false): string {
  if (typeof value !== 'string' || value.length > 100) throw new HomeError('Выберите часовой пояс.');
  let zone: string;
  try { zone = new Intl.DateTimeFormat('en', {timeZone:value}).resolvedOptions().timeZone; }
  catch { throw new HomeError('Выберите часовой пояс.'); }
  // Opening another browser, travelling, or adding an owner does not move existing schedules.
  if (!initialize || !store.getSetting(key)) store.setSetting(key,zone);
  return ownerTimezone(store);
}
