import { afterEach, expect, it, vi } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";
import { TelegramAdapter } from "../src/telegram.js";
import { HttpApi } from "../src/server.js";
import { digest } from "../src/home.js";
import { homeRequest, requestJSON, resultJSON } from "../src/home-transport.js";

const nativeFetch = globalThis.fetch;
const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const close of cleanups.splice(0)) await close(); vi.unstubAllGlobals(); });
async function setup(destinations: Record<string, unknown> = { chatId: "42" }) {
  const root = mkdtempSync(join(tmpdir(), "strudel-notification-"));
  const store = new Store(join(root, "db.sqlite"));
  store.linkTelegramChat({ chatId: "42", title: "Owner", allowedSenders: ["42"] });
  store.linkTelegramChat({ chatId: "-100", title: "Team", allowedSenders: [] }); store.connectTelegramGroup("-100");
  store.setSetting("telegram.notification_hook", JSON.stringify({ ...destinations, tokenHash: digest("notification-secret") }));
  const engine = { run: vi.fn(async () => { throw new Error("Notifications must not run an agent"); }) };
  const messages = new MessageService(store, engine, root);
  const telegram = new TelegramAdapter("1:test", store, messages);
  const api = new HttpApi(store, messages, telegram, "owner-secret", undefined, engine, { mobileDirectory: join(root, "mobile"), mobilePort: 0 });
  const address = await api.listen("127.0.0.1", 0);
  const send = vi.fn(async () => Response.json({ ok: true, result: { message_id: 123 } }));
  vi.stubGlobal("fetch", send);
  const post = (body: unknown, key = "meeting-card:one:v1", token = "notification-secret") => nativeFetch(`http://127.0.0.1:${address.port}/hooks/telegram`, {
    method: "POST", headers: { authorization: "Bearer " + token, "content-type": "application/json", "idempotency-key": key }, body: JSON.stringify(body),
  });
  cleanups.push(async () => { await api.close(); telegram.stop(); await messages.close(); store.close(); rmSync(root, { recursive: true, force: true }); });
  return { store, engine, send, api, post, base: `http://127.0.0.1:${address.port}` };
}

it("relays the supplied text once to the configured chat and records it without running AI", async () => {
  const { post, store, engine, send } = await setup();
  const body = { text: "Meeting ready", chatId: "999", sessionId: "one", summary: "Do not forward extra fields" };
  const first = await post(body); expect(first.status).toBe(200);
  const receipt = await first.json(); expect(receipt).toMatchObject({ sent: true, chatId: "42", status: "delivered" });
  expect((await post(body)).status).toBe(200); expect(send).toHaveBeenCalledTimes(1);
  expect(JSON.parse(String(send.mock.calls[0]?.[1]?.body))).toMatchObject({ chat_id: "42", text: "Meeting ready" });
  expect(store.findMessageByExternal("telegram", "notification:" + digest("42\0meeting-card:one:v1"))?.text).toBe("Meeting ready");
  expect(engine.run).not.toHaveBeenCalled();
});

it("rejects missing or wrong credentials and never grants API access to a notification token", async () => {
  const { post, send, base, store } = await setup();
  for (const token of ["", "wrong", "owner-secret"]) expect((await post({ text: "No" }, "one", token)).status).toBe(401);
  expect((await nativeFetch(base + "/v1/profiles", { headers: { authorization: "Bearer notification-secret" } })).status).toBe(401);
  store.setSetting("telegram.notification_hook", "null");
  expect((await post({ text: "No" })).status).toBe(401);
  expect(send).not.toHaveBeenCalled();
});

it("rejects missing identity, empty text and changed content on a repeated identity", async () => {
  const { post, send } = await setup();
  expect((await post({ text: "No" }, "")).status).toBe(400);
  expect((await post({ text: "" })).status).toBe(400);
  expect((await post({ text: "Original" })).status).toBe(200);
  expect((await post({ text: "Replacement" })).status).toBe(409);
  expect(send).toHaveBeenCalledTimes(1);
});

it("does not acknowledge or repeat an uncertain Telegram delivery", async () => {
  const { post, send } = await setup(); send.mockRejectedValue(new Error("connection lost"));
  expect((await post({ text: "Once" })).status).toBe(502);
  expect((await post({ text: "Once" })).status).toBe(502);
  expect(send).toHaveBeenCalledTimes(1);
});

it("relays one notification to every listed chat once, each under its own identity", async () => {
  const { post, store, send } = await setup({ chatIds: ["42", "-100"] });
  const first = await post({ text: "Meeting ready" }); expect(first.status).toBe(200);
  expect(await first.json()).toMatchObject({ sent: true, status: "delivered", chatId: "42", deliveries: [
    { sent: true, status: "delivered", chatId: "42", title: "Owner", telegramMessageIds: ["123"] },
    { sent: true, status: "delivered", chatId: "-100", title: "Team", telegramMessageIds: ["123"] }] });
  expect((await post({ text: "Meeting ready" })).status).toBe(200);
  expect(send.mock.calls.map(call => JSON.parse(String(call[1]?.body)).chat_id)).toEqual(["42", "-100"]);
  for (const chatId of ["42", "-100"]) expect(store.findMessageByExternal("telegram", "notification:" + digest(chatId + "\0meeting-card:one:v1"))?.text).toBe("Meeting ready");
});

it("keeps the single-chat receipt when one chat is listed", async () => {
  const { post } = await setup({ chatIds: ["42"] });
  const receipt = await (await post({ text: "Meeting ready" })).json();
  expect(Object.keys(receipt).sort()).toEqual(["chatId", "messageId", "sent", "status", "telegramMessageIds", "title"]);
  expect(receipt).toMatchObject({ sent: true, status: "delivered", chatId: "42", title: "Owner", telegramMessageIds: ["123"] });
});

it("accepts 1 to 10 distinct chat ids", async () => {
  const { post, store, send } = await setup();
  const ids = Array.from({ length: 11 }, (_, index) => String(index + 1));
  const configure = (chatIds: unknown) => store.setSetting("telegram.notification_hook", JSON.stringify({ chatIds, tokenHash: digest("notification-secret") }));
  for (const chatIds of [[], ["42", "42"], ids, ["42", "team"], "42"]) { configure(chatIds); expect((await post({ text: "No" })).status, JSON.stringify(chatIds)).toBe(401); }
  // Ten unconnected chats pass the setting check and then fail as destinations.
  configure(ids.slice(0, 10)); expect((await post({ text: "No" })).status).toBe(400);
  expect(send).not.toHaveBeenCalled();
});

it("sends nothing unless every listed chat can receive it", async () => {
  const { post, store, send } = await setup({ chatIds: ["42", "-100"] });
  store.setSetting("telegram.paused.-100", "true");
  const paused = await post({ text: "Meeting ready" });
  expect(paused.status).toBe(400); expect(await paused.json()).toEqual({ error: "Бот больше не подключён к этому чату." });
  store.deleteSetting("telegram.paused.-100"); store.db.prepare("DELETE FROM telegram_chats WHERE chat_id='-100'").run();
  expect((await post({ text: "Meeting ready" })).status).toBe(400);
  expect(send).not.toHaveBeenCalled();
});

it("answers 502 with each chat's receipt and resends to none after a partly confirmed delivery", async () => {
  const { post, send } = await setup({ chatIds: ["42", "-100"] });
  send.mockImplementationOnce(async () => Response.json({ ok: true, result: { message_id: 123 } })).mockRejectedValueOnce(new Error("connection lost"));
  for (const attempt of [1, 2]) {
    const response = await post({ text: "Once" }); expect(response.status, `attempt ${attempt}`).toBe(502);
    expect(await response.json()).toMatchObject({ error: "Доставка не подтверждена; проверьте Telegram перед новой отправкой.", sent: false, status: "unknown", chatId: "42",
      deliveries: [{ chatId: "42", sent: true, status: "delivered" }, { chatId: "-100", sent: false, status: "unknown" }] });
  }
  expect((await post({ text: "Changed" })).status).toBe(409);
  expect(send).toHaveBeenCalledTimes(2);
});

it("reports a chat that Telegram refused as a partial delivery", async () => {
  const { post, send } = await setup({ chatIds: ["42", "-100"] });
  send.mockImplementation(async (_url: string, init?: RequestInit) => JSON.parse(String(init?.body)).chat_id === "-100"
    ? Response.json({ ok: false, error_code: 403, description: "Forbidden: bot was kicked" }, { status: 403 })
    : Response.json({ ok: true, result: { message_id: 123 } }));
  const response = await post({ text: "Once" }); expect(response.status).toBe(502);
  expect(await response.json()).toMatchObject({ sent: false, status: "partial", deliveries: [{ status: "delivered" }, { status: "not_sent" }] });
});

it("uses the same scoped authentication through the remote HTTPS listener", async () => {
  const { api, send } = await setup();
  const endpoint = await api.mobile.endpoint(); const url = new URL(endpoint.url); url.hostname = "127.0.0.1";
  const remote = { ...endpoint, url: url.toString() };
  const request = { method: "POST", body: requestJSON({ text: "Remote meeting" }) };
  expect((await homeRequest(remote, "/hooks/telegram", "wrong", request, 5000, { "idempotency-key": "remote:1" })).status).toBe(401);
  const response = await homeRequest(remote, "/hooks/telegram", "notification-secret", request, 5000, { "idempotency-key": "remote:1" });
  expect(response.status).toBe(200); expect(resultJSON(response).sent).toBe(true); expect(send).toHaveBeenCalledTimes(1);
});
