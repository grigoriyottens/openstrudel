import { timingSafeEqual } from "node:crypto";
import { digest, HomeError } from "./home.js";
import type { Store } from "./store.js";
import type { TelegramAdapter } from "./telegram.js";

/** This credential can only relay text to its preconfigured, connected chats. */
export function notificationDestinations(store: Store, authorization?: string): string[] {
  let config: { chatId?: unknown; chatIds?: unknown; tokenHash?: unknown } = {};
  try { config = JSON.parse(store.getSetting("telegram.notification_hook") ?? "{}") ?? {}; } catch {}
  const token = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  const chatIds = config.chatIds ?? [config.chatId];
  if (!token || !Array.isArray(chatIds) || !chatIds.length || chatIds.length > 10 || new Set(chatIds).size < chatIds.length
      || chatIds.some(chatId => typeof chatId !== "string" || !/^-?\d+$/.test(chatId))
      || typeof config.tokenHash !== "string" || !/^[a-f0-9]{64}$/.test(config.tokenHash)
      || !timingSafeEqual(Buffer.from(digest(token), "hex"), Buffer.from(config.tokenHash, "hex"))) {
    throw new HomeError("unauthorized", 401);
  }
  return chatIds;
}

const UNCONFIRMED = "Доставка не подтверждена; проверьте Telegram перед новой отправкой.";

/** Answers 200 only when every chat confirmed delivery, because the sender treats any other answer as a failure. */
export async function receiveNotification(store: Store, telegram: TelegramAdapter, chatIds: string[], key: string | string[] | undefined, body: Record<string, unknown>): Promise<[number, object]> {
  if (typeof key !== "string" || !/^[A-Za-z0-9._:-]{1,200}$/.test(key)) throw new HomeError("Укажите Idempotency-Key.", 400);
  if (typeof body.text !== "string" || !body.text.trim()) throw new HomeError("Нужен текст сообщения.", 400);
  const text = body.text.trim();
  // Each chat keeps its own identity, so repeating the request never sends to the same chat twice.
  const deliveries = chatIds.map(chatId => ({ chatId, text, files: [], externalId: "notification:" + digest(chatId + "\0" + key) }));
  for (const { chatId, externalId } of deliveries) {
    const previous = store.findMessageByExternal("telegram", externalId);
    if (previous && previous.text !== text) throw new HomeError("Содержимое уведомления изменилось.", 409);
    // Nothing is sent unless every chat can receive it.
    telegram.deliveryTarget(chatId, externalId);
  }
  const receipts = [];
  for (const delivery of deliveries) receipts.push(await telegram.sendToChat(delivery));
  if (receipts.length === 1) return receipts[0]!.sent ? [200, receipts[0]!] : [502, { error: UNCONFIRMED }];
  const sent = receipts.every(r => r.sent), statuses = receipts.map(r => r.status);
  const status = sent ? "delivered" : ["unknown", "pending"].find(state => statuses.includes(state)) ?? (statuses.every(state => state === "not_sent") ? "not_sent" : "partial");
  const receipt = { sent, status, chatId: chatIds[0], deliveries: receipts };
  // With several chats, a failure still says which chats were reached.
  return sent ? [200, receipt] : [502, { error: UNCONFIRMED, ...receipt }];
}
