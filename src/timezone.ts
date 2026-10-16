import type { Store } from './store.js';
import { HomeError } from './home.js';

const key = 'owner.timezone';
export function ownerTimezone(store: Store): string | null {
  // A server's UTC clock says nothing about the person using it.
  return store.getSetting(key);
}
export function saveOwnerTimezone(store: Store, value: unknown, initialize = false): string {
  if (typeof value !== 'string' || value.length > 100) throw new HomeError('Выберите часовой пояс.');
  let zone: string;
  try { zone = new Intl.DateTimeFormat('en', {timeZone:value}).resolvedOptions().timeZone; }
  catch { throw new HomeError('Выберите часовой пояс.'); }
  // Opening another browser, travelling, or adding an owner does not move existing schedules.
  if (!initialize || !store.getSetting(key)) store.setSetting(key,zone);
  return ownerTimezone(store)!;
}

export function scheduleTimezone(store: Store, value: unknown, existing?: string): string {
  const zone = typeof value === 'string' && value.trim() ? value.trim() : existing ?? ownerTimezone(store);
  if (!zone) throw new HomeError('Часовой пояс ещё не задан. Уточните город или часовой пояс для этого расписания.');
  try { return new Intl.DateTimeFormat('en', {timeZone:zone}).resolvedOptions().timeZone; }
  catch { throw new HomeError('Выберите часовой пояс.'); }
}

export function localScheduleTime(instant: string, timezone: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone:timezone, weekday:'long',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23' }).format(new Date(instant)) + ` (${timezone})`;
}
