import { CronExpressionParser } from "cron-parser";

/** Keep the existing string wire contract: old Codex threads retain their tool
 * schema. @once adds an absolute time without rewriting their saved history. */
export function scheduleTiming(expression: string, timezone: string, now = new Date()): { once: boolean; nextRunAt: string } {
  new Intl.DateTimeFormat("en", { timeZone: timezone }).format(now);
  const value = expression.trim();
  if (value.startsWith("@once ")) {
    const timestamp = value.slice(6);
    const match = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.\d{1,3})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/.exec(timestamp);
    if (!match) throw new Error("Для разового напоминания укажите @once и дату ISO 8601 с часовым поясом.");
    const [year, month, day] = match.slice(1, 4).map(Number) as [number, number, number];
    const date = new Date(timestamp), calendar = new Date(0);
    calendar.setUTCFullYear(year, month - 1, day);
    if (!Number.isFinite(date.getTime()) || calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 || calendar.getUTCDate() !== day) {
      throw new Error("Проверьте дату напоминания.");
    }
    return { once: true, nextRunAt: date.toISOString() };
  }
  if (value.split(/\s+/).length !== 5) throw new Error("Укажите пять полей cron или @once с датой и часовым поясом.");
  return { once: false, nextRunAt: CronExpressionParser.parse(value, { currentDate: now, tz: timezone }).next().toISOString()! };
}
