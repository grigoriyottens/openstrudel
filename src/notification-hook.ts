import { timingSafeEqual } from "node:crypto";
import { digest, HomeError } from "./home.js";
import type { Store } from "./store.js";
import type { TelegramAdapter } from "./telegram.js";

/** This credential can only relay text to one preconfigured, connected chat. */
export function notificationDestination(store: Store, authorization?: string): string {
  let config: { chatId?: unknown; tokenHash?: unknown } = {};
  try { config = JSON.parse(store.getSetting("telegram.notification_hook") ?? "{}") ?? {}; } catch {}
  const token = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token || typeof config.chatId !== "string" || !/^-?\d+$/.test(config.chatId)
      || typeof config.tokenHash !== "string" || !/^[a-f0-9]{64}$/.test(config.tokenHash)
      || !timingSafeEqual(Buffer.from(digest(token), "hex"), Buffer.from(config.tokenHash, "hex"))) {
    throw new HomeError("unauthorized", 401);
  }
  return config.chatId;
}

export async function receiveNotification(store: Store, telegram: TelegramAdapter, chatId: string, key: string | string[] | undefined, body: Record<string, unknown>) {
  if (typeof key !== "string" || !/^[A-Za-z0-9._:-]{1,200}$/.test(key)) throw new HomeError("Укажите Idempotency-Key.", 400);
  if (typeof body.text !== "string" || !body.text.trim() || body.text.length > 32_000) throw new HomeError("Нужен текст до 32 000 символов.", 400);
  const text = body.text.trim();
  const externalId = "notification:" + digest(chatId + "\0" + key);
  const previous = store.findMessageByExternal("telegram", externalId);
  if (previous && previous.text !== text) throw new HomeError("Содержимое уведомления изменилось.", 409);
  const receipt = await telegram.sendToChat({ chatId, text, files: [], externalId });
  if (!receipt.sent) throw new HomeError("Доставка не подтверждена; проверьте Telegram перед новой отправкой.", 502);
  return receipt;
}
