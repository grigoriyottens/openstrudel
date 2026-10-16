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
async function setup() {
  const root = mkdtempSync(join(tmpdir(), "strudel-notification-"));
  const store = new Store(join(root, "db.sqlite"));
  store.linkTelegramChat({ chatId: "42", title: "Owner", allowedSenders: ["42"] });
  store.setSetting("telegram.notification_hook", JSON.stringify({ chatId: "42", tokenHash: digest("notification-secret") }));
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

it("uses the same scoped authentication through the remote HTTPS listener", async () => {
  const { api, send } = await setup();
  const endpoint = await api.mobile.endpoint(); const url = new URL(endpoint.url); url.hostname = "127.0.0.1";
  const remote = { ...endpoint, url: url.toString() };
  const request = { method: "POST", body: requestJSON({ text: "Remote meeting" }) };
  expect((await homeRequest(remote, "/hooks/telegram", "wrong", request, 5000, { "idempotency-key": "remote:1" })).status).toBe(401);
  const response = await homeRequest(remote, "/hooks/telegram", "notification-secret", request, 5000, { "idempotency-key": "remote:1" });
  expect(response.status).toBe(200); expect(resultJSON(response).sent).toBe(true); expect(send).toHaveBeenCalledTimes(1);
});
