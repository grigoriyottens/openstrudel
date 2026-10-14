import { afterEach, expect, it, vi } from "vitest";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";
import { TelegramAdapter } from "../src/telegram.js";

const stores: Store[] = [];
afterEach(() => { vi.unstubAllGlobals(); for (const store of stores.splice(0)) store.close(); });
function fixture() {
  const store = new Store(":memory:"); stores.push(store);
  const profile = store.createProfile({ name: "Editor" });
  const app = store.profileConversation(profile.id);
  const groups = ["-1001234567890", "-1001234567891"].map((chatId, i) => {
    store.linkTelegramChat({ chatId, title: "Team " + (i + 1), allowedSenders: ["7"] });
    return store.bindTelegramChat(chatId, profile.id);
  });
  return { store, profile, app, groups };
}

it("pages one employee's accepted requests across audiences without mixing context or other employees", () => {
  const { store, profile, app, groups } = fixture();
  const messages = Array.from({ length: 127 }, (_, i) => store.addMessage({
    conversationId: i % 2 ? groups[0]!.conversationId! : app.id,
    channel: i % 2 ? "telegram" : "api", direction: "inbound", text: String(i),
    ...(i % 2 ? { externalId: groups[0]!.chatId + ":" + (i + 1), author: "Dasha" } : {}),
  }));
  store.db.prepare("UPDATE messages SET created_at=?").run("2026-10-14T00:00:00.000Z");
  const chatter = store.addMessage({ conversationId: groups[1]!.conversationId!, channel: "telegram", direction: "inbound", text: "Ordinary chat" });
  store.db.prepare("UPDATE messages SET context_only=1 WHERE id=?").run(chatter.id);
  const foreign = store.addMessage({ conversationId: store.profileConversation(store.createProfile({ name: "Other" }).id).id, channel: "api", direction: "inbound", text: "Private" });
  const page = store.employeeMessagePage(profile.id, new URLSearchParams("limit=50"));
  const middle = store.employeeMessagePage(profile.id, new URLSearchParams({ before: page.pagination.olderCursor!, limit: "50" }));
  const first = store.employeeMessagePage(profile.id, new URLSearchParams({ before: middle.pagination.olderCursor!, limit: "50" }));
  expect([...first.messages, ...middle.messages, ...page.messages].map(m => m.id)).toEqual(messages.map(m => m.id));
  expect(page.messages.find(m => m.channel === "telegram")).toMatchObject({ author: "Dasha", origin: { channel: "telegram", title: "Team 1", chatId: groups[0]!.chatId } });
  expect(first.messages[1]?.origin?.url).toBe("https://t.me/c/1234567890/2");
  expect(() => store.employeeMessagePage(profile.id, new URLSearchParams({ after: foreign.id }))).toThrow();
  expect(store.listMessages(groups[1]!.conversationId!)).toHaveLength(1);
});

it("removes a silently declined request from a loaded timeline while retaining its context and cursor", async () => {
  const { store, profile, groups } = fixture();
  let finish!: (v: any) => void;
  const messages = new MessageService(store, { run: () => new Promise(resolve => { finish = resolve; }) });
  const turn = await messages.submit({ channel: "telegram", conversationId: groups[0]!.conversationId!, externalChatId: groups[0]!.chatId, externalId: groups[0]!.chatId + ":1", text: "Not for the bot" });
  await vi.waitFor(() => expect(finish).toBeTypeOf("function"));
  const initial = store.employeeMessagePage(profile.id, new URLSearchParams());
  expect(initial.messages).toHaveLength(1);
  finish({ threadId: "test", response: "NO_REPLY", events: [] });
  await turn.completion;
  const delta = store.employeeMessagePage(profile.id, new URLSearchParams({ after: initial.pagination.newerCursor!, watch: turn.receipt.messageId }));
  expect(delta.messages).toEqual([]);
  expect(delta.removedIds).toEqual([turn.receipt.messageId]);
  expect(store.listMessages(groups[0]!.conversationId!)).toHaveLength(1);
  await messages.close();
});

it("updates Telegram delivery without resending ambiguous chunks or assigning old history to a new employee", async () => {
  const { store, profile, groups } = fixture();
  const service = new MessageService(store, { run: async () => ({ threadId: "test", response: "Done", events: [] }) });
  const adapter = new TelegramAdapter("123:synthetic", store, service);
  const inbound = store.addMessage({ conversationId: groups[0]!.conversationId!, channel: "telegram", direction: "inbound", text: "Do it", externalId: groups[0]!.chatId + ":11" });
  const reply = store.addMessage({ conversationId: inbound.conversationId, channel: "telegram", direction: "outbound", replyToId: inbound.id, text: "Done" });
  vi.stubGlobal("fetch", vi.fn(async () => Response.json({ ok: true, result: { message_id: 12 } })));
  await adapter.sendMessage(groups[0]!.chatId, reply.text, "reply:" + reply.id);
  const delivered = store.employeeMessagePage(profile.id, new URLSearchParams({ after: reply.id, watch: reply.id })).updates[0]!;
  expect(delivered.delivery?.state).toBe("delivered");
  expect(delivered.origin?.url).toBe("https://t.me/c/1234567890/12");
  store.db.prepare("UPDATE telegram_outbox SET status='unknown',error='Lost acknowledgement'").run();
  expect(store.employeeMessagePage(profile.id, new URLSearchParams()).messages.at(-1)?.delivery?.state).toBe("unknown");
  const next = store.createProfile({ name: "New employee" });
  store.bindTelegramChat(groups[0]!.chatId, next.id);
  expect(store.employeeMessagePage(next.id, new URLSearchParams()).messages).toEqual([]);
  const old = store.employeeMessagePage(profile.id, new URLSearchParams()).messages;
  expect(old.map(m => m.id)).toEqual([inbound.id, reply.id]);
  expect(old[0]?.origin?.canReply).toBe(false);
  expect(fetch).toHaveBeenCalledTimes(1);
  await service.close();
});

it("keeps imported history without an employee reachable from the main assistant", () => {
  const { store, profile } = fixture();
  const archive = store.getOrCreateConversation({ channel: "api", externalId: "import::legacy", title: "Old team" });
  store.importHistory(archive.id, [{ sourceId: "one", date: "2026-09-01", author: "Dasha", direction: "inbound", text: "Remember this" }]);
  expect(store.employeeMessagePage(null, new URLSearchParams()).messages[0]).toMatchObject({ text: "Remember this", origin: { channel: "archive", title: "Old team" } });
  expect(store.employeeMessagePage(profile.id, new URLSearchParams()).messages).toEqual([]);
});

it("sends an explicit owner reply once to its exact Telegram message and rejects a changed audience", async () => {
  const { store, profile, groups } = fixture();
  const run = vi.fn(async () => ({ threadId: "unused", response: "unused", events: [] }));
  const service = new MessageService(store, { run });
  const adapter = new TelegramAdapter("123:synthetic", store, service);
  const input = store.addMessage({ conversationId: groups[0]!.conversationId!, channel: "telegram", direction: "inbound", text: "Question", externalId: groups[0]!.chatId + ":11" });
  vi.stubGlobal("fetch", vi.fn(async () => Response.json({ ok: true, result: { message_id: 12 } })));
  const first = await adapter.replyFromApp({ conversationId: input.conversationId, replyToId: input.id, text: "Confirmed", externalId: "11111111-1111-4111-8111-111111111111" });
  const second = await adapter.replyFromApp({ conversationId: input.conversationId, replyToId: input.id, text: "Confirmed", externalId: "11111111-1111-4111-8111-111111111111" });
  expect(first.messageId).toBe(second.messageId);
  expect(fetch).toHaveBeenCalledTimes(1);
  expect(JSON.parse(String(vi.mocked(fetch).mock.calls[0]![1]!.body))).toMatchObject({ chat_id: groups[0]!.chatId, reply_parameters: { message_id: 11 } });
  expect(run).not.toHaveBeenCalled();
  const reply = store.employeeMessagePage(profile.id, new URLSearchParams()).messages.at(-1)!;
  expect(reply).toMatchObject({ text: "Confirmed", replyToId: input.id, author: "OpenStrudel", delivery: { state: "delivered" } });
  store.bindTelegramChat(groups[0]!.chatId, store.createProfile({ name: "Replacement" }).id);
  await expect(adapter.replyFromApp({ conversationId: input.conversationId, replyToId: input.id, text: "Do not send", externalId: "22222222-2222-4222-8222-222222222222" })).rejects.toThrow();
  expect(fetch).toHaveBeenCalledTimes(1);
  await service.close();
});

it("retains an ambiguous app reply across retries and rejects changed text, paused groups and foreign files", async () => {
  const { store, groups } = fixture();
  const service = new MessageService(store, { run: async () => { throw new Error("Must not run"); } });
  const adapter = new TelegramAdapter("123:synthetic", store, service);
  const inbound = store.addMessage({ conversationId: groups[0]!.conversationId!, channel: "telegram", direction: "inbound", text: "Question", externalId: groups[0]!.chatId + ":11" });
  const input = { conversationId: inbound.conversationId, replyToId: inbound.id, text: "Reply", externalId: "11111111-1111-4111-8111-111111111111" };
  vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("Connection lost after send"); }));
  const receipt = await adapter.replyFromApp(input);
  expect(store.employeeMessagePage(store.getConversation(inbound.conversationId)!.profileId, new URLSearchParams()).messages.at(-1)?.delivery?.state).toBe("unknown");
  expect(await adapter.replyFromApp(input)).toEqual(receipt);
  await expect(adapter.replyFromApp({ ...input, text: "Changed" })).rejects.toThrow();
  expect(fetch).toHaveBeenCalledTimes(1);
  store.setSetting("telegram.paused." + groups[0]!.chatId, "true");
  await expect(adapter.replyFromApp({ ...input, externalId: "22222222-2222-4222-8222-222222222222" })).rejects.toThrow();
  await expect(adapter.replyFromApp({ ...input, attachments: ["missing"] })).rejects.toThrow();
  expect(fetch).toHaveBeenCalledTimes(1);
  await service.close();
});
